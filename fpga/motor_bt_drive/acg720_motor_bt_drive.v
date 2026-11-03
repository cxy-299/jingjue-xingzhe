// BTD4 蓝牙四向离地试验：GUI 按住方向持续刷新，松开 S 停车，无需 S1。
// S0 急停、蓝牙看门狗、连续运行限时及编码器故障均关闭全部电机。
module acg720_motor_bt_drive #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 20_000,
    parameter integer BT_BAUD = 9_600,
    parameter integer DIAG_BAUD = 115_200,
    parameter integer STARTUP_MS = 20,
    parameter integer STAGGER_MS = 40,
    parameter integer KICK_MS = 100,
    parameter integer TARGET_COUNTS = 20,
    parameter integer LOSS_TICKS = 20,
    parameter integer BT_TIMEOUT_MS = 300,
    parameter integer NEUTRAL_MS = 100,
    parameter integer RUN_LIMIT_MS = 3_000,
    parameter integer AUTO_NAV_ENABLE = 0,
    parameter [15:0] AUTO_MAP_ID = 16'h2612,
    parameter [399:0] AUTO_MAP_BITS = 0,
    parameter integer MISSION_ENABLE = 0,
    parameter integer VISUAL_PRIMARY_ENABLE = 0, // experimental smart mission only
    parameter integer ROTATE_ENABLE = 0,
    parameter integer VISION_ENABLE = 0,
    parameter integer NAV_ENABLE = 0,
    parameter integer SENSOR_ENABLE = 0,
    parameter integer SENSOR_IMU_BAUD = 115_200,
    parameter integer SENSOR_TOF_BAUD = 115_200,
    parameter integer TOF_HARD_STOP_MM = 250,
    parameter integer NAV_CELL_COUNTS = 1000,
    parameter integer DIAG_ENABLE = 1,
    parameter integer REV5_ENABLE = 0
) (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire bt_uart_rx_i,
    input wire pi_uart_rx_i,
    input wire imu_uart_rx_i,
    input wire tof0_uart_rx_i,
    input wire [3:0] encoder_a_i,
    input wire [3:0] encoder_b_i,
    output wire [3:0] motor_pwm_o,
    output wire [3:0] motor_in1_o,
    output wire [3:0] motor_in2_o,
    output wire [5:0] led_o,
    output wire diag_uart_tx_o,
    output wire bt_uart_tx_o
);
    localparam integer SAMPLE_CYCLES = CLK_HZ / 100 < 1 ? 1 : CLK_HZ / 100;
    localparam integer STAGGER_CYCLES = (CLK_HZ / 1000) * STAGGER_MS;
    localparam integer KICK_CYCLES = (CLK_HZ / 1000) * KICK_MS < 1 ? 1 : (CLK_HZ / 1000) * KICK_MS;
    localparam integer STARTUP_CYCLES = (CLK_HZ / 1000) * STARTUP_MS < 1 ? 1 : (CLK_HZ / 1000) * STARTUP_MS;
    localparam [2:0] STOP = 0, FORWARD = 1, BACKWARD = 2, LEFT = 3, RIGHT = 4,
                     ROTATE_CCW = 5, ROTATE_CW = 6;
    reg [31:0] startup_count = 0;
    reg [25:0] heartbeat_count = 0;
    reg ready = 0;
    wire mission_request,mission_active;
    wire [31:0] mission_id,mission_lock;
    wire [15:0] mission_class,mission_speed;
    wire [4:0] mission_state;
    wire [2:0] mission_command,mission_leg;
    wire pi_packet,pi_selected,pi_present,pi_confirmed,pi_red;
    wire [31:0] pi_mission,pi_lock;
    wire [15:0] pi_class,pi_seq;
    wire signed [15:0] pi_center;
    wire pi_geometry_valid,pi_geometry_beam;
    wire signed [15:0] pi_geometry_yaw;
    wire [15:0] pi_geometry_range,pi_geometry_uncertainty,pi_geometry_age;
    wire [31:0] pi_geometry_frame;
    wire heading_yaw_valid;
    wire auto_request,auto_active,auto_fault,tof_sample;
    wire [7:0] auto_state,auto_reason,auto_replans,auto_x,auto_y,auto_gx,auto_gy,auto_ox,auto_oy;
    wire [15:0] auto_sequence,auto_speed;
    wire [2:0] auto_command;
    wire [7:0] bt_data;
    wire bt_valid, bt_framing_error;
    wire bt_ascii_valid;
    wire turn_request, turn_active, turn_fault;
    wire [15:0] turn_seq,turn_speed;
    wire [3:0] turn_state;
    wire [2:0] turn_command;
    wire signed [15:0] turn_yaw,turn_target_yaw,turn_error;
    wire [2:0] command;
    wire [15:0] target_counts;
    wire bt_timeout_seen, bt_framing_fault;
    wire [3:0] channel_enable, channel_fault, feedback_seen;
    wire [11:0] wheel_fault_reason;
    wire [63:0] wheel_fault_speed, wheel_fault_duty;
    wire signed [31:0] wheel_position [0:3];
    wire signed [15:0] speed [0:3];
    wire signed [15:0] encoder_speed_raw [0:3];
    wire signed [15:0] duty [0:3];
    wire nav_goal_pulse, nav_route_ready, nav_no_path, nav_waypoint_valid;
    wire nav_advance, nav_active, nav_done, nav_fault;
    wire [7:0] nav_goal_x, nav_goal_y, nav_waypoint_x, nav_waypoint_y;
    wire [2:0] nav_command;
    wire [7:0] nav_step_count;
    wire [127:0] nav_route_bits;
    wire [31:0] imu_roll_raw;
    wire [31:0] imu_pitch_raw;
    wire [31:0] imu_yaw_raw;
    wire imu_angle_valid;
    wire [15:0] tof0_distance_mm;
    wire [3:0] tof_valid;
    wire tof_obstacle;
    wire tof_hard_stop;
    // R7: internal owner/state decisions use a registered ToF stop. The
    // physical enable below always checks the live stop as well as this
    // trailing copy, so assertion is immediate and a one-cycle stop cannot
    // resurrect a command while its owner is being canceled.
    (* syn_preserve=1 *) reg tof_hard_stop_q=1;
    wire control_tof_stop=REV5_ENABLE>=3 ? tof_hard_stop_q : tof_hard_stop;
    always @(posedge clk_50m_i or negedge key_s0_n_i)begin
        if(!key_s0_n_i)tof_hard_stop_q<=1;
        else if(!ready)tof_hard_stop_q<=1;
        else tof_hard_stop_q<=tof_hard_stop;
    end
    wire tof_decel;
    wire vision_active, vision_fresh, vision_selected, vision_visible;
    wire [15:0] vision_class, vision_target;
    wire [31:0] vision_lock;
    wire [3:0] vision_state;
    wire [2:0] vision_command;
    wire nav_cancel = control_tof_stop || auto_active || auto_request || mission_active || mission_request || vision_active || turn_active || turn_request ||
                      (bt_ascii_valid && !bt_framing_error && bt_data == "S");
    wire [9:0] tof_speed_scale_permille;
    wire [15:0] tof_nearest_mm;
    // Limit the PI speed reference, rather than halving the PI PWM output.
    // Cutting PWM after the controller can stall a slow wheel and latch a
    // false no-feedback fault while approaching a ToF obstacle.
    // The owners retain their original priority. Decode once, then balance
    // the data selection without inserting a cycle into command or stop gates.
    wire owner_auto = auto_active;
    wire owner_mission = !auto_active && mission_active;
    wire owner_turn = !(auto_active || mission_active) && turn_active;
    wire owner_vision = !(auto_active || mission_active || turn_active) && vision_active;
    wire owner_manual = !(auto_active || mission_active || turn_active || vision_active);
    wire owner_nav = owner_manual && NAV_ENABLE && nav_active;
    wire owner_bt = owner_manual && !(NAV_ENABLE && nav_active);
    wire [15:0] selected_target_raw =
        ({16{owner_auto}} & auto_speed) |
        ({16{owner_mission}} & mission_speed) |
        ({16{owner_turn}} & turn_speed) |
        ({16{owner_vision}} & vision_target) |
        ({16{owner_manual}} & target_counts);
    wire [15:0] selected_target;
    wire [2:0] selected_command_raw =
        ({3{owner_auto}} & auto_command) |
        ({3{owner_mission}} & mission_command) |
        ({3{owner_turn}} & turn_command) |
        ({3{owner_vision}} & vision_command) |
        ({3{owner_nav}} & nav_command) |
        ({3{owner_bt}} & command);
    wire [2:0] effective_command;
    // SIN12 has six command owners. Break the packet/guard/owner mux path
    // before wheel control; the independent S0/ToF/motor-fault gates below
    // still remove physical output without waiting for these registers.
    generate if (AUTO_NAV_ENABLE) begin : g_owner_pipeline
        reg [15:0] target_q=0;
        reg [2:0] command_q=STOP;
        always @(posedge clk_50m_i or negedge key_s0_n_i) begin
            if (!key_s0_n_i) begin target_q<=0;command_q<=STOP;end
            else begin target_q<=selected_target_raw;command_q<=selected_command_raw;end
        end
        assign selected_target=target_q;
        assign effective_command=command_q;
    end else begin : g_owner_direct
        assign selected_target=selected_target_raw;
        assign effective_command=selected_command_raw;
    end endgenerate
    wire [15:0] effective_target_counts = !SENSOR_ENABLE ? selected_target :
        tof_hard_stop ? 16'd0 :
        // R20 single-ToF front end: use its original500/800mm bands directly
        // instead of encoding10-bit permille then decoding it again before PID.
        // Same-cycle formula and live hard-stop gate are unchanged.
        REV5_ENABLE>=16 ? (tof0_distance_mm>=800 ? selected_target :
            tof0_distance_mm>=500 ? selected_target-(selected_target>>2):(selected_target>>1)) :
        (tof_speed_scale_permille >= 10'd1000) ? selected_target :
        (tof_speed_scale_permille >= 10'd750) ?
            selected_target - (selected_target >> 2) : (selected_target >> 1);
    wire sensor_imu_valid_led = SENSOR_ENABLE && imu_angle_valid;
    wire [7:0] fault_flags = {2'b00, turn_fault, (|channel_fault), (nav_fault || auto_fault),
                              bt_framing_fault, bt_timeout_seen,
                              (SENSOR_ENABLE && tof_hard_stop)};
    reg [31:0] run_age = 0;
    reg [31:0] sample_count = 0;
    reg sample_tick = 0;
    reg sample_tick_d = 0;

    // 逻辑轮序 M1=前左、M2=前右、M3=后左、M4=后右。
    // 左/右为麦克纳姆横移的目标轮速符号，实际横移方向仍须落地验证滚轮安装。
    wire [3:0] desired_forward = effective_command == FORWARD ? 4'b1111 :
                                 effective_command == BACKWARD ? 4'b0000 :
                                 effective_command == LEFT ? 4'b1001 :
                                 effective_command == RIGHT ? 4'b0110 :
                                 effective_command == ROTATE_CCW ? 4'b1010 :
                                 effective_command == ROTATE_CW ? 4'b0101 : 4'b0000;
    wire [2:0] owner_id=auto_active ? 1 : mission_active ? 2 : turn_active ? 3 : vision_active ? 4 : nav_active ? 5 : 0;
    wire [63:0] wheel_targets;
    wire heading_locked;
    wire signed [15:0] heading_reference,heading_error;
    wire signed [7:0] heading_correction;
    wire [5:0] pid_p,pid_i,pid_d;
    wire [15:0] pid_sequence;
    wire [1:0] pid_status;
    wire pid_changed;
    wire clear_block,avoid_enabled,avoid_capture,avoid_request,avoid_lease,avoid_cancel,auto_local,avoid_inhibit,avoid_resume;
    wire [1:0] recovery_result;
    wire [7:0] control_ack_sequence;
    wire [7:0] avoid_state,avoid_reason;
    wire [15:0] avoid_sequence;
    wire [3:0] blocked_mask,severe_mask;
    wire [39:0] control_status={control_ack_sequence,{4'd0,recovery_result,avoid_capture,avoid_enabled},avoid_state,avoid_reason,{severe_mask,blocked_mask}};
    // Stillness is invariant under wheel polarity. Use the encoder register
    // directly; owner-command sign muxes must not feed quiet qualification.
    wire common_still=(encoder_speed_raw[0]>=-1 && encoder_speed_raw[0]<=1 && encoder_speed_raw[1]>=-1 && encoder_speed_raw[1]<=1 &&
                       encoder_speed_raw[2]>=-1 && encoder_speed_raw[2]<=1 && encoder_speed_raw[3]>=-1 && encoder_speed_raw[3]<=1);
    wire motor_enable = key_s0_n_i && ready && effective_command != STOP &&
                        !(|channel_fault) && !bt_framing_fault &&
                        !(SENSOR_ENABLE && (tof_hard_stop || (REV5_ENABLE>=3 && tof_hard_stop_q))) &&
                        (!AUTO_NAV_ENABLE || !SENSOR_ENABLE || !ROTATE_ENABLE || heading_yaw_valid);
    wire interlocked_enable;
    // Internal PID state may trail the physical gate by one 50MHz cycle.
    // PWM/IN still use channel_enable directly for immediate hard shutdown.
    reg [3:0] control_enable_q=0;
    always @(posedge clk_50m_i or negedge key_s0_n_i)begin
        if(!key_s0_n_i)control_enable_q<=0;
        else control_enable_q<={4{interlocked_enable}};
    end
    generate if (AUTO_NAV_ENABLE) begin : g_direction_interlock
        motor_direction_interlock #(.QUIET_CYCLES((CLK_HZ/1000)*NEUTRAL_MS)) u_interlock(
            .clk(clk_50m_i),.rst_n(key_s0_n_i),.request_i(motor_enable),
            .command_i(effective_command),.enable_o(interlocked_enable));
    end else begin : g_legacy_enable
        assign interlocked_enable=motor_enable;
    end endgenerate

    // 任务1/3传感器前端。当前整车先接一只车头 ToF，其他三路置空闲高电平。
    // sensor_task1_3_core 对无效/超时数据采取停车策略，避免传感器断线时继续行驶。
    generate if (SENSOR_ENABLE) begin : g_sensor_frontend
        sensor_task1_3_core #(.CLK_HZ(CLK_HZ), .IMU_BAUD(SENSOR_IMU_BAUD),
            .TOF_BAUD(SENSOR_TOF_BAUD), .TOF_COUNT(1),
            .HARD_STOP_MM(TOF_HARD_STOP_MM)) u_sensor (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
            .imu_uart_rx_i(imu_uart_rx_i), .tof0_uart_rx_i(tof0_uart_rx_i),
            .tof1_uart_rx_i(1'b1), .tof2_uart_rx_i(1'b1), .tof3_uart_rx_i(1'b1),
            .roll_raw_o(imu_roll_raw), .pitch_raw_o(imu_pitch_raw), .yaw_raw_o(imu_yaw_raw),
            .imu_angle_valid_o(imu_angle_valid), .tof0_distance_mm_o(tof0_distance_mm),
            .tof1_distance_mm_o(), .tof2_distance_mm_o(), .tof3_distance_mm_o(),
            .tof_valid_o(tof_valid), .tof_obstacle_o(tof_obstacle),
            .tof_hard_stop_o(tof_hard_stop), .tof_decel_o(tof_decel),
            .tof_speed_scale_permille_o(tof_speed_scale_permille),
            .tof_nearest_mm_o(tof_nearest_mm), .tof0_sample_o(tof_sample)
        );
    end else begin : g_no_sensor_frontend
        assign imu_roll_raw = 0; assign imu_pitch_raw = 0; assign imu_yaw_raw = 0;
        assign imu_angle_valid = 1'b0; assign tof0_distance_mm = 0;
        assign tof_valid = 0; assign tof_obstacle = 1'b0; assign tof_hard_stop = 1'b0;
        assign tof_decel = 1'b0; assign tof_speed_scale_permille = 10'd1000;
        assign tof_nearest_mm = 16'hffff; assign tof_sample=0;
    end endgenerate

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            startup_count <= 0;
            heartbeat_count <= 0;
            ready <= 0;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;
            if (!ready) begin
                if (startup_count >= STARTUP_CYCLES - 1) ready <= 1;
                else startup_count <= startup_count + 1'b1;
            end
        end
    end

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BT_BAUD)) u_bt_rx (
        .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
        .uart_rx_i(bt_uart_rx_i), .data_o(bt_data),
        .data_valid_o(bt_valid), .framing_error_o(bt_framing_error)
    );
    bt_motion_guard #(
        .CLK_HZ(CLK_HZ), .TIMEOUT_MS(BT_TIMEOUT_MS), .NEUTRAL_MS(NEUTRAL_MS),
        .RUN_LIMIT_MS(RUN_LIMIT_MS),.CONTINUATION_ENABLE(REV5_ENABLE>=2)
    ) u_bt_guard (
        .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
        .armed_i(ready), .force_stop_i((SENSOR_ENABLE && (control_tof_stop || (AUTO_NAV_ENABLE && ROTATE_ENABLE && !heading_yaw_valid))) || auto_active || turn_active || mission_active || avoid_capture || avoid_inhibit),
        .resume_forward_i(avoid_resume),.rx_data_i(bt_data), .rx_valid_i(bt_ascii_valid),
        .framing_error_i(bt_framing_error), .command_o(command),
        .target_counts_o(target_counts),
        .timeout_seen_o(bt_timeout_seen), .framing_fault_o(bt_framing_fault)
    );

    generate if(ROTATE_ENABLE)begin:g_heading
        wire signed [15:0] requested_angle;
        wire [15:0] requested_seq;
        wire [7:0] requested_speed;
        wire requested_inverted;
        bt_turn_packet_rx #(.BYTE_TIMEOUT_CYCLES((CLK_HZ/1000)*20)) u_packet(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.byte_i(bt_data),
            .valid_i(bt_valid),.error_i(bt_framing_error),.ascii_valid_o(bt_ascii_valid),
            .request_o(turn_request),.sequence_o(requested_seq),.angle_o(requested_angle),
            .speed_o(requested_speed),.inverted_o(requested_inverted));
        yaw_float_to_q13 u_yaw(.clk(clk_50m_i),.rst_n(key_s0_n_i && ready),
            .bits_i(imu_yaw_raw),.recent_i(imu_angle_valid),.yaw_o(turn_yaw),.valid_o(heading_yaw_valid));
        imu_turn_guard #(.CLK_HZ(CLK_HZ),.PIPELINED_TARGET(REV5_ENABLE>=3),.DAMPED_APPROACH(REV5_ENABLE>=5)) u_turn(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.sample_tick_i(sample_tick_d),
            .request_i(turn_request),.sequence_i(requested_seq),.angle_cdeg_i(requested_angle),
            .speed_i(requested_speed),.inverted_i(requested_inverted),.yaw_i(turn_yaw),
            .sensors_ok_i(heading_yaw_valid && tof_valid[0]),.hard_stop_i(control_tof_stop),
            .motor_fault_i(|channel_fault),.other_active_i(auto_active || nav_active || vision_active || mission_active || command!=STOP),
            .cancel_i(auto_active || auto_request || nav_goal_pulse || mission_request || mission_active),.ascii_valid_i(bt_ascii_valid),.error_i(bt_framing_error),.ascii_i(bt_data),
            .active_o(turn_active),.fault_o(turn_fault),.state_o(turn_state),.sequence_o(turn_seq),
            .target_yaw_o(turn_target_yaw),.error_o(turn_error),.command_o(turn_command),.target_speed_o(turn_speed));
    end else begin:g_no_heading
        assign bt_ascii_valid=bt_valid;
        assign turn_request=0;assign turn_active=0;assign turn_fault=0;
        assign turn_state=0;assign turn_seq=0;assign turn_speed=0;assign turn_command=0;
        assign turn_yaw=0;assign turn_target_yaw=0;assign turn_error=0;assign heading_yaw_valid=0;
    end endgenerate

    generate if(REV5_ENABLE && AUTO_NAV_ENABLE)begin:g_manual_safety
        motor_recovery_guard u_recovery(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.sample_tick_i(sample_tick_d),
            // With every owner inactive, selected_command_raw is command.
            // Do not feed the safety-gated owner mux back into quiet timing.
            .stopped_i(command==STOP && effective_command==STOP && !auto_active && !mission_active && !turn_active && !vision_active && !nav_active && !avoid_capture),
            .sensors_clear_i(heading_yaw_valid && tof_valid[0] && !control_tof_stop),
            .ascii_valid_i(bt_ascii_valid),.error_i(bt_framing_error),.ascii_i(bt_data),
            .speed0_i(encoder_speed_raw[0]),.speed1_i(encoder_speed_raw[1]),.speed2_i(encoder_speed_raw[2]),.speed3_i(encoder_speed_raw[3]),
            .blocked_i(blocked_mask),.severe_i(severe_mask),.clear_block_o(clear_block),
            .avoid_enabled_o(avoid_enabled),.recovery_result_o(recovery_result),.ack_sequence_o(control_ack_sequence));
        manual_avoid_bridge #(.CONTINUE_ENABLE(REV5_ENABLE>=2)) u_avoid(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.sample_tick_i(sample_tick_d),
            .enabled_i(avoid_enabled),.sensors_ok_i(heading_yaw_valid && tof_valid[0]),
            .hard_stop_i(control_tof_stop),.motor_fault_i(|channel_fault),.manual_command_i(command),
            .stopped_i(common_still && !interlocked_enable && command==STOP),
            .other_active_i(mission_active || turn_active || vision_active || nav_active || mission_request || turn_request || nav_goal_pulse || auto_request),
            .tof_sample_i(tof_sample),.distance_i(tof0_distance_mm),
            .ascii_valid_i(bt_ascii_valid),.error_i(bt_framing_error),.ascii_i(bt_data),
            .nav_active_i(auto_active),.nav_local_i(auto_local),.nav_state_i(auto_state),.nav_sequence_i(auto_sequence),
            .capture_o(avoid_capture),.request_o(avoid_request),.sequence_o(avoid_sequence),
            .lease_pulse_o(avoid_lease),.cancel_o(avoid_cancel),.state_o(avoid_state),.reason_o(avoid_reason),.inhibit_o(avoid_inhibit),.resume_o(avoid_resume));
    end else begin:g_no_manual_safety
        assign clear_block=0;assign avoid_enabled=0;assign recovery_result=0;assign control_ack_sequence=0;
        assign avoid_capture=0;assign avoid_request=0;assign avoid_lease=0;assign avoid_cancel=0;assign avoid_inhibit=0;assign avoid_resume=0;
        assign avoid_state=0;assign avoid_reason=0;assign avoid_sequence=0;
    end endgenerate

    generate if (VISION_ENABLE) begin : g_pi_vision
        wire [7:0] data;
        wire valid, frame_error, packet, selected, follow, present, confirmed;
        wire [15:0] class_id, sequence_id;
        wire [31:0] lock_id;
        wire signed [15:0] center_error;
        uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) u_rx (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && ready), .uart_rx_i(pi_uart_rx_i),
            .data_o(data), .data_valid_o(valid), .framing_error_o(frame_error));
        vision_packet_parser #(.ENABLE_VISUAL_PRIMARY(VISUAL_PRIMARY_ENABLE),.BYTE_TIMEOUT_CYCLES(CLK_HZ/50)) u_parser (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
            .byte_i(data), .byte_valid_i(valid && !frame_error),
            .vision_valid_o(packet), .selection_valid_o(selected),
            .follow_requested_o(follow), .lock_id_o(lock_id),
            .target_present_o(present), .target_confirmed_o(confirmed),
            .class_id_o(class_id), .center_error_o(center_error), .sequence_o(sequence_id),
            .mission_id_o(pi_mission),.mission_red_o(pi_red),
            .geometry_valid_o(pi_geometry_valid),.geometry_beam_o(pi_geometry_beam),
            .geometry_yaw_o(pi_geometry_yaw),.geometry_range_o(pi_geometry_range),
            .geometry_uncertainty_o(pi_geometry_uncertainty),.geometry_age_o(pi_geometry_age),
            .heartbeat_valid_o(),.nav_goal_valid_o(),.nav_goal_x_o(),.nav_goal_y_o(),
            .target_centered_o(),.alignment_o(),.confidence_o(),.center_x_o(),.center_y_o(),
            .width_o(),.height_o(),.area_ratio_o(),.frame_id_o(pi_geometry_frame),.crc_error_count_o());
        assign pi_packet=packet;assign pi_selected=selected;assign pi_present=present;
        assign pi_confirmed=confirmed;assign pi_lock=lock_id;assign pi_class=class_id;
        assign pi_seq=sequence_id;assign pi_center=center_error;
        vision_follow_guard #(.CLK_HZ(CLK_HZ)) u_follow (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
            .packet_i(packet), .selected_i(selected), .visible_i(present),
            .confirmed_i(confirmed), .follow_i(follow), .sequence_i(sequence_id),
            .class_i(class_id), .lock_i(lock_id), .center_i(center_error),
            .bt_valid_i(bt_ascii_valid), .bt_error_i(bt_framing_error), .bt_byte_i(bt_data),
            .hard_stop_i(control_tof_stop), .sensors_ok_i(tof_valid[0] && imu_angle_valid),
            .motor_fault_i(|channel_fault), .nav_start_i(auto_active || auto_request || nav_goal_pulse || turn_request || mission_request || mission_active),
            .distance_i(tof0_distance_mm), .active_o(vision_active),
            .fresh_o(vision_fresh), .selected_o(vision_selected), .visible_o(vision_visible),
            .class_o(vision_class), .lock_o(vision_lock), .state_o(vision_state),
            .command_o(vision_command), .target_o(vision_target));
    end else begin : g_no_pi_vision
        assign pi_packet=0;assign pi_selected=0;assign pi_present=0;assign pi_confirmed=0;
        assign pi_geometry_valid=0;assign pi_geometry_beam=0;assign pi_geometry_yaw=0;
        assign pi_geometry_range=0;assign pi_geometry_uncertainty=0;assign pi_geometry_age=16'hffff;
        assign pi_geometry_frame=0;
        assign pi_mission=0;assign pi_lock=0;assign pi_class=0;assign pi_seq=0;assign pi_center=0;assign pi_red=0;
        assign vision_active=0; assign vision_fresh=0; assign vision_selected=0;
        assign vision_visible=0; assign vision_class=16'hffff; assign vision_lock=0;
        assign vision_state=0; assign vision_command=0; assign vision_target=0;
    end endgenerate

    generate if(MISSION_ENABLE)begin:g_mission
        wire [31:0] rid;wire [15:0] rc,rd;wire red,inverted;
        bt_mission_packet_rx #(.BYTE_TIMEOUT_CYCLES((CLK_HZ/1000)*20)) u_request(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.byte_i(bt_data),.valid_i(bt_valid),
            .error_i(bt_framing_error),.request_o(mission_request),.mission_o(rid),.class_o(rc),
            .distance_o(rd),.red_o(red),.inverted_o(inverted),.ascii_valid_o(),.sequence_o(),.angle_o(),.speed_o());
        // R15: tolerate the recorded417ms host scheduling gap only for the
        // vision mission. All other owners retain their original watchdogs.
        vision_mission_guard #(.VISUAL_PRIMARY(VISUAL_PRIMARY_ENABLE),.CLK_HZ(CLK_HZ),.LEASE_MS(REV5_ENABLE>=11?600:300),.CONTROLLED_ALIGN(REV5_ENABLE>=6),.MISSION_REFINEMENT(REV5_ENABLE>=7),.PERSISTENT_REACQUIRE(REV5_ENABLE>=10),.RECOVERY_SEARCH(REV5_ENABLE>=11),.RECOVERY_RUN_MS(100),.RECOVERY_REST_MS(REV5_ENABLE>=12?1000:300),.RECOVERY_WAIT_MS(REV5_ENABLE>=12?1000:300),.RECOVERY_SPEED(4),.ALIGN_REST_MS(REV5_ENABLE>=12?1000:300),.APPROACH_REST_MS(300),.OBSERVE_SETTLE_MS(REV5_ENABLE>=12?1000:0),.TWO_STAGE_APPROACH(REV5_ENABLE>=13)) u_guard(
            .geometry_frame_i(pi_geometry_frame),.geometry_valid_i(pi_geometry_valid),.geometry_beam_i(pi_geometry_beam),
            .geometry_yaw_i(pi_geometry_yaw),.geometry_range_i(pi_geometry_range),
            .geometry_uncertainty_i(pi_geometry_uncertainty),.geometry_age_i(pi_geometry_age),
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.sample_tick_i(sample_tick_d),
            .request_i(mission_request),.request_id_i(rid),.request_class_i(rc),.request_distance_i(rd),
            .request_red_i(red),.request_inverted_i(inverted),.packet_i(pi_packet),.packet_sequence_i(pi_seq),
            .packet_mission_i(pi_mission),.packet_lock_i(pi_lock),.packet_class_i(pi_class),.packet_red_i(pi_red),
            .selected_i(pi_selected),.visible_i(pi_present),.confirmed_i(pi_confirmed),.center_i(pi_center),
            .yaw_i(turn_yaw),.distance_i(tof0_distance_mm),.distance_sample_i(tof_sample),.sensors_ok_i(heading_yaw_valid && tof_valid[0]),
            .wheels_still_i(common_still),
            .hard_stop_i(control_tof_stop),.motor_fault_i(|channel_fault),
            .other_active_i(auto_active || turn_active || vision_active || nav_active || command!=STOP),
            .cancel_i(auto_active || auto_request || nav_goal_pulse || turn_request),.ascii_valid_i(bt_ascii_valid),
            .ascii_i(bt_data),.error_i(bt_framing_error),.active_o(mission_active),.id_o(mission_id),
            .lock_o(mission_lock),.class_o(mission_class),.state_o(mission_state),.leg_o(mission_leg),
            .command_o(mission_command),.speed_o(mission_speed));
    end else begin:g_no_mission
        assign mission_request=0;assign mission_active=0;assign mission_id=0;assign mission_lock=0;
        assign mission_class=16'hffff;assign mission_state=0;assign mission_leg=0;
        assign mission_command=0;assign mission_speed=0;
    end endgenerate
    // R16 provisional straight calibration; legacy lateral executor is unchanged.
    // R18 follows the user's R12 ground measurement:1000 counts/200mm.
    // Only onboard navigation/manual-F local detours change; route/mission/PID do not.
    localparam integer AUTO_GRID_COUNTS=REV5_ENABLE>=14 ? 500 : REV5_ENABLE>=12 ? 333 : NAV_CELL_COUNTS;
    generate if(AUTO_NAV_ENABLE)begin:g_autonav
        wire [7:0] sx,sy,gx,gy,flags,velocity;
        wire [15:0] seq,counts;
        wire signed [15:0] setback;
        bt_autonav_packet_rx #(.BYTE_TIMEOUT_CYCLES((CLK_HZ/1000)*20),.MAP_ID(AUTO_MAP_ID)) u_packet(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.byte_i(bt_data),.valid_i(bt_valid),
            .error_i(bt_framing_error),.request_o(auto_request),.sequence_o(seq),
            .sx_o(sx),.sy_o(sy),.gx_o(gx),.gy_o(gy),.counts_o(counts),.setback_o(setback),.flags_o(flags),.speed_o(velocity));
        autonomous_nav_guard #(.CELL_COUNTS(AUTO_GRID_COUNTS),.MAP_BITS(AUTO_MAP_BITS),.LOCAL_MAP_ENABLE(REV5_ENABLE),.CANCEL_PIPELINE(REV5_ENABLE>=2),.PROGRESS_CONTROL(REV5_ENABLE>=5),.CONFIRMED_MAPPING(REV5_ENABLE>=11),.ROUND_POSE_MM(REV5_ENABLE>=12),.FIXED_LEFT_DETOUR(REV5_ENABLE>=14),.DETOUR_FORWARD_CELLS(REV5_ENABLE>=15?3:1),.LATCH_NEAR_EVENT(REV5_ENABLE>=15),.EARLY_STOP_MM(REV5_ENABLE>=16?200:400),.ADAPTIVE_DETOUR(REV5_ENABLE>=16),.CONSERVATIVE_CELLS(REV5_ENABLE>=16)) u_guard(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.sample_tick_i(sample_tick_d),
            .request_i(auto_request || avoid_request),.sequence_i(auto_request?seq:avoid_sequence),
            .sx_i(auto_request?sx:8'd10),.sy_i(auto_request?sy:8'd5),.gx_i(auto_request?gx:8'd10),.gy_i(auto_request?gy:8'd15),
            .counts_i(auto_request?counts:AUTO_GRID_COUNTS[15:0]),.setback_i(auto_request?setback:16'sd0),
            .flags_i(auto_request?flags:8'd5),.speed_i(auto_request?velocity:8'd8),.yaw_i(turn_yaw),
            .sensors_ok_i(heading_yaw_valid && tof_valid[0]),.hard_stop_i(control_tof_stop),.motor_fault_i(|channel_fault),
            .other_active_i(mission_active || turn_active || vision_active || nav_active || command!=STOP),
            .cancel_i(avoid_cancel || mission_request || turn_request || nav_goal_pulse || mission_active || turn_active || vision_active ||
                (bt_ascii_valid && ((bt_data=="F" && !avoid_capture) || bt_data=="B" || bt_data=="L" || bt_data=="R" || bt_data=="V"))),
            .ascii_valid_i(bt_ascii_valid),.ascii_i(avoid_lease ? "N":bt_data),.error_i(bt_framing_error),
            .tof_sample_i(tof_sample),.distance_i(tof0_distance_mm),
            .position0_i(wheel_position[0]),.position1_i(wheel_position[1]),
            .position2_i(wheel_position[2]),.position3_i(wheel_position[3]),
            .active_o(auto_active),.fault_o(auto_fault),.state_o(auto_state),.reason_o(auto_reason),
            .replans_o(auto_replans),.sequence_o(auto_sequence),.local_mode_o(auto_local),.x_o(auto_x),.y_o(auto_y),
            .gx_o(auto_gx),.gy_o(auto_gy),.obstacle_x_o(auto_ox),.obstacle_y_o(auto_oy),.command_o(auto_command),.speed_o(auto_speed));
    end else begin:g_no_autonav
        assign auto_request=0;assign auto_active=0;assign auto_fault=0;assign auto_state=0;
        assign auto_reason=0;assign auto_replans=0;assign auto_sequence=0;
        assign auto_x=0;assign auto_y=0;assign auto_gx=0;assign auto_gy=0;
        assign auto_command=0;assign auto_speed=0;assign auto_ox=255;assign auto_oy=255;
        assign auto_local=0;
    end endgenerate

    // BTD5 默认不综合导航逻辑；BTD6 包装顶层通过 NAV_ENABLE=1 打开。
    // 导航与手动遥控共用 9600 baud 输入。GUI/Pi 在固定地图上计算路径，
    // FPGA 只接受带 CRC 的完整路径帧，并用编码器逐格闭环执行。
    generate if (NAV_ENABLE) begin : g_navigation
        nav_path_parser #(.BYTE_TIMEOUT_CYCLES((CLK_HZ / 1000) * 20)) u_nav_parser (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
            .byte_i(bt_data), .byte_valid_i(bt_valid),
            .route_valid_o(nav_goal_pulse), .goal_x_o(nav_goal_x),
            .goal_y_o(nav_goal_y), .map_ok_o(), .step_count_o(nav_step_count),
            .route_bits_o(nav_route_bits), .crc_error_count_o(), .last_crc_calc_o()
        );
        nav_route_executor #(.CELL_COUNTS(NAV_CELL_COUNTS),
            .PROGRESS_PIPELINE(REV5_ENABLE>=11)) u_nav_route (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
            .sample_tick_i(sample_tick_d), .route_valid_i(nav_goal_pulse && !auto_active && !turn_active && !mission_active),
            .step_count_i(nav_step_count), .route_bits_i(nav_route_bits),
            .position0_i(wheel_position[0]), .position1_i(wheel_position[1]),
            .position2_i(wheel_position[2]), .position3_i(wheel_position[3]),
            .cancel_i(nav_cancel),
            .active_o(nav_active), .advance_o(nav_advance), .done_o(nav_done),
            .fault_o(nav_fault), .command_o(nav_command)
        );
        assign nav_route_ready = nav_goal_pulse;
        assign nav_no_path = nav_fault;
        assign nav_waypoint_valid = nav_active;
        assign nav_waypoint_x = 0; assign nav_waypoint_y = 0;
    end else begin : g_no_navigation
        assign nav_goal_pulse = 1'b0;
        assign nav_route_ready = 1'b0;
        assign nav_no_path = 1'b0;
        assign nav_waypoint_valid = 1'b0;
        assign nav_advance = 1'b0;
        assign nav_active = 1'b0;
        assign nav_done = 1'b0;
        assign nav_fault = 1'b0;
        assign nav_goal_x = 8'd0; assign nav_goal_y = 8'd0;
        assign nav_waypoint_x = 8'd0; assign nav_waypoint_y = 8'd0;
        assign nav_command = STOP;
        assign nav_step_count = 0; assign nav_route_bits = 0;
    end endgenerate

    always @(posedge clk_50m_i or negedge key_s0_n_i) begin
        if (!key_s0_n_i) begin
            run_age <= 0; sample_count <= 0; sample_tick <= 0; sample_tick_d <= 0;
        end else begin
            sample_tick_d <= sample_tick;
            sample_tick <= 0;
            if (sample_count >= SAMPLE_CYCLES - 1) begin
                sample_count <= 0; sample_tick <= 1;
            end else sample_count <= sample_count + 1'b1;
            if (!interlocked_enable) run_age <= 0;
            else if (run_age < 3 * STAGGER_CYCLES) run_age <= run_age + 1'b1;
        end
    end

    generate if(AUTO_NAV_ENABLE)begin:g_trim
        chassis_trim #(.PHYSICAL_SPEEDS(REV5_ENABLE>=2),.LATERAL_HEADING(REV5_ENABLE>=6),.MISSION_PULSED(REV5_ENABLE>=7)) u_trim(.clk(clk_50m_i),.rst_n(key_s0_n_i),.sample_tick_i(sample_tick_d),
            .enable_i(interlocked_enable),.yaw_valid_i(heading_yaw_valid || !ROTATE_ENABLE),.command_i(effective_command),.owner_i(owner_id),
            .yaw_i(turn_yaw),.base_i(effective_target_counts),
            .speed0_i(REV5_ENABLE>=2 ? encoder_speed_raw[0]:speed[0]),.speed1_i(REV5_ENABLE>=2 ? -$signed(encoder_speed_raw[1]):speed[1]),.speed2_i(REV5_ENABLE>=2 ? encoder_speed_raw[2]:speed[2]),.speed3_i(REV5_ENABLE>=2 ? -$signed(encoder_speed_raw[3]):speed[3]),
            .targets_o(wheel_targets),.heading_locked_o(heading_locked),.reference_o(heading_reference),
            .error_o(heading_error),.correction_o(heading_correction));
        // Request owners remain busy during neutral gaps and settling, not just PWM.
        // Require a quiet 250 ms, and encoder standstill on fresh shared samples.
        reg [31:0] stopped_age=0;
        reg wheels_still=0;
        // Inactive owners plus manual STOP imply selected_command_raw==STOP.
        // effective_command also checks the trailing owner pipeline register.
        wire owner_stopped=effective_command==STOP &&
            !auto_active && !mission_active && !turn_active && !vision_active && !nav_active && command==STOP;
        always @(posedge clk_50m_i or negedge key_s0_n_i)begin
            if(!key_s0_n_i)begin stopped_age<=0;wheels_still<=0;end
            else begin
                if(sample_tick_d)wheels_still<=speed[0]>=-1 && speed[0]<=1 && speed[1]>=-1 && speed[1]<=1 &&
                    speed[2]>=-1 && speed[2]<=1 && speed[3]>=-1 && speed[3]<=1;
                // owner_stopped implies effective_command==STOP, which forces
                // motor_enable/interlocked_enable/channel_enable low already.
                if(!owner_stopped || !wheels_still)stopped_age<=0;
                else if(stopped_age<(CLK_HZ/4))stopped_age<=stopped_age+1'b1;
            end
        end
        bt_pid_config #(.BYTE_TIMEOUT_CYCLES((CLK_HZ/1000)*20)) u_pid(
            .clk(clk_50m_i),.rst_n(key_s0_n_i && ready),.byte_i(bt_data),.valid_i(bt_valid),.error_i(bt_framing_error),
            .stopped_i(owner_stopped && wheels_still && stopped_age>=CLK_HZ/4),
            .p_o(pid_p),.i_o(pid_i),.d_o(pid_d),.sequence_o(pid_sequence),.status_o(pid_status),.changed_o(pid_changed));
    end else begin:g_no_trim
        assign wheel_targets={4{effective_target_counts}};
        assign heading_locked=0;assign heading_reference=0;assign heading_error=0;assign heading_correction=0;
        assign pid_p=4;assign pid_i=1;assign pid_d=0;assign pid_sequence=0;assign pid_status=0;assign pid_changed=0;
    end endgenerate

    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : wheels
        assign blocked_mask[i]=channel_fault[i] && wheel_fault_reason[i*3+:3]==3'd1;
        assign severe_mask[i]=channel_fault[i] && wheel_fault_reason[i*3+:3]!=3'd1;
        wire signed [15:0] raw_speed;
        wire signed [16:0] forward_speed = (i == 0 || i == 2) ? $signed(raw_speed) : -$signed(raw_speed);
        wire signed [16:0] directed_speed = desired_forward[i] ? forward_speed : -forward_speed;
        wire [31:0] unused_position;
        wire signed [15:0] wheel_duty;
        wire signed [15:0] applied_duty = tof_hard_stop && SENSOR_ENABLE ? 16'sd0 : wheel_duty;
        wire forward_in1 = (i == 1 || i == 3);
        wire selected_in1 = desired_forward[i] ? forward_in1 : !forward_in1;
        // SIN12 moves a chassis: every wheel must start on the same cycle.
        // Staggering remains available only to historical bring-up fixtures.
        assign channel_enable[i] = interlocked_enable &&
            (AUTO_NAV_ENABLE ? wheel_targets[i*16+:16]!=0 : run_age >= i * STAGGER_CYCLES);
        assign motor_in1_o[i] = channel_enable[i] && selected_in1;
        assign motor_in2_o[i] = channel_enable[i] && !selected_in1;
        assign speed[i] = directed_speed[15:0];
        assign encoder_speed_raw[i] = raw_speed;
        assign duty[i] = applied_duty;
        encoder_speed #(.FILTER_CYCLES(AUTO_NAV_ENABLE ? 50 : 1)) u_encoder (
            .clk(clk_50m_i), .rst_n(key_s0_n_i),
            .encoder_a_i(encoder_a_i[i]), .encoder_b_i(encoder_b_i[i]),
            .sample_tick_i(sample_tick), .position_o(wheel_position[i]), .speed_o(raw_speed)
        );
        motor_four_pi_channel #(
            .KICK_CYCLES(KICK_CYCLES), .KICK_RAMP_ENABLE(AUTO_NAV_ENABLE), .RUNTIME_PID_ENABLE(AUTO_NAV_ENABLE),
            .RECOVERABLE_BLOCK_ENABLE(REV5_ENABLE),
            .TARGET_COUNTS(TARGET_COUNTS),
            .LOSS_TICKS(LOSS_TICKS)
        ) u_control (
            .clk(clk_50m_i), .rst_n(key_s0_n_i), .enable_i(AUTO_NAV_ENABLE ? control_enable_q[i] : channel_enable[i]),
            .sample_tick_i(sample_tick_d), .forward_speed_i(directed_speed),
            .target_counts_i(wheel_targets[i*16+:16]),
            .kp_i(pid_p),.ki_i(pid_i),.kd_i(pid_d),
            .feedback_start_i(REV5_ENABLE || effective_command==ROTATE_CCW || effective_command==ROTATE_CW),.clear_block_i(clear_block),
            .duty_o(wheel_duty), .fault_o(channel_fault[i]),
            .feedback_seen_o(feedback_seen[i]),
            .fault_reason_o(wheel_fault_reason[i*3 +: 3]),
            .fault_speed_o(wheel_fault_speed[i*16 +: 16]),
            .fault_duty_o(wheel_fault_duty[i*16 +: 16])
        );
        motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm (
            .clk(clk_50m_i), .rst_n(key_s0_n_i && ready),
            .enable_i(channel_enable[i]), .duty_i(applied_duty),
            .pwm_o(motor_pwm_o[i]), .direction_o()
        );
    end endgenerate

    // LED2 心跳、LED3 就绪、LED4 输出、LED5 蓝牙/IMU有效、LED6 反馈、LED7 告警。
    assign led_o = {|fault_flags,
                    &feedback_seen, bt_timeout_seen || sensor_imu_valid_led,
                    |channel_enable, ready, heartbeat_count[23]};

    // 板载 CH340 串口持续轮询四轮诊断；手机蓝牙端只承担命令输入。
    generate if(MISSION_ENABLE)begin:g_mission_pi_diag
    bt_combined_diag_uart #(
        .CLK_HZ(CLK_HZ), .BAUD(DIAG_BAUD), .TARGET_COUNTS(TARGET_COUNTS),
        .TELEMETRY_DIV(10), .VISION_ENABLE(VISION_ENABLE), .ROTATE_ENABLE(ROTATE_ENABLE), .MISSION_ENABLE(MISSION_ENABLE), .AUTO_NAV_ENABLE(AUTO_NAV_ENABLE), .R4_ENABLE(AUTO_NAV_ENABLE), .REV5_ENABLE(REV5_ENABLE)
    ) u_pi_diag (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .sample_tick_i(sample_tick_d),
        .pid_p_i(pid_p),.pid_i_i(pid_i),.pid_d_i(pid_d),.pid_sequence_i(pid_sequence),.pid_status_i(pid_status),
        .wheel_targets_i(wheel_targets),.command_i(effective_command),.heading_locked_i(heading_locked),
        .heading_reference_i(heading_reference),.heading_error_i(heading_error),.heading_correction_i(heading_correction),.control_status_i(control_status),
        .wheel_fault_reason_i(wheel_fault_reason), .wheel_fault_speed_i(wheel_fault_speed),
        .wheel_fault_duty_i(wheel_fault_duty),
        .target_counts_i(effective_target_counts),
        .speed0_i(speed[0]), .speed1_i(speed[1]), .speed2_i(speed[2]), .speed3_i(speed[3]),
        .duty_gate_i(channel_enable),
        .duty0_i((REV5_ENABLE>=2 || channel_enable[0]) ? duty[0] : 16'sd0),
        .duty1_i((REV5_ENABLE>=2 || channel_enable[1]) ? duty[1] : 16'sd0),
        .duty2_i((REV5_ENABLE>=2 || channel_enable[2]) ? duty[2] : 16'sd0),
        .duty3_i((REV5_ENABLE>=2 || channel_enable[3]) ? duty[3] : 16'sd0),
        .fault_i(led_o[5]),
        .imu_valid_i(imu_angle_valid), .tof_valid_i(tof_valid[0]),
        .sensor_distance_i(tof0_distance_mm), .sensor_hard_stop_i(tof_hard_stop),
        .sensor_roll_i(imu_roll_raw), .sensor_pitch_i(imu_pitch_raw), .sensor_yaw_i(imu_yaw_raw),
        .sensor_fault_i(fault_flags), .sensor_wheel_fault_i(channel_fault),
        .vision_fresh_i(vision_fresh), .vision_visible_i(vision_visible),
        .vision_class_i(vision_class), .vision_lock_i(vision_lock),
        .vision_state_i(vision_state), .vision_active_i(vision_active),
        .turn_active_i(turn_active), .turn_sequence_i(turn_seq), .turn_state_i(turn_state),
        .turn_yaw_i(turn_yaw),.turn_target_i(turn_target_yaw),.turn_error_i(turn_error),
        .mission_active_i(mission_active),.mission_id_i(mission_id),.mission_class_i(mission_class),
        .mission_lock_i(mission_lock),.mission_state_i(mission_state),.mission_leg_i(mission_leg),
        .auto_active_i(auto_active),.auto_sequence_i(auto_sequence),.auto_state_i(auto_state | (auto_local ? 8'h80:8'h00)),.auto_reason_i(auto_reason),
        .auto_x_i(auto_x),.auto_y_i(auto_y),.auto_gx_i(auto_gx),.auto_gy_i(auto_gy),.auto_replans_i(auto_replans),.auto_ox_i(auto_ox),.auto_oy_i(auto_oy),
        .uart_tx_o(diag_uart_tx_o)
    );
    end else if (SENSOR_ENABLE) begin : g_sensor_diag_uart
        sensor_status_uart #(.CLK_HZ(CLK_HZ), .BAUD(DIAG_BAUD)) u_sensor_status (
            .clk(clk_50m_i), .rst_n(key_s0_n_i),
            .imu_valid_i(imu_angle_valid), .tof_valid_i(tof_valid[0]),
            .distance_i(tof0_distance_mm), .hard_stop_i(tof_hard_stop),
            .roll_bits_i(imu_roll_raw), .pitch_bits_i(imu_pitch_raw),
            .yaw_bits_i(imu_yaw_raw), .fault_flags_i(fault_flags),
            .wheel_fault_i(channel_fault),
            .tx_o(diag_uart_tx_o)
        );
    end else if (DIAG_ENABLE) begin : g_diag_uart
        motor_four_diag_uart #(.CLK_HZ(CLK_HZ), .BAUD(DIAG_BAUD), .TARGET_COUNTS(TARGET_COUNTS)) u_diag (
            .clk(clk_50m_i), .rst_n(key_s0_n_i), .sample_tick_i(sample_tick_d),
            .target_counts_i(effective_target_counts),
            .speed0_i(speed[0]), .speed1_i(speed[1]), .speed2_i(speed[2]), .speed3_i(speed[3]),
            .duty0_i(channel_enable[0] ? duty[0] : 16'sd0),
            .duty1_i(channel_enable[1] ? duty[1] : 16'sd0),
            .duty2_i(channel_enable[2] ? duty[2] : 16'sd0),
            .duty3_i(channel_enable[3] ? duty[3] : 16'sd0),
            .fault_i(led_o[5]), .uart_tx_o(diag_uart_tx_o)
        );
    end else begin : g_no_diag_uart
        assign diag_uart_tx_o = 1'b1;
    end endgenerate

    // 蓝牙回传与命令共用 ZS-040 的另一条 UART 线；9600 baud 交替发送
    // 四轮闭环帧和 IMU/ToF 状态帧。COM6/M15 仍保留 115200 备用。
    bt_combined_diag_uart #(
        .CLK_HZ(CLK_HZ), .BAUD(BT_BAUD), .TARGET_COUNTS(TARGET_COUNTS),
        .TELEMETRY_DIV(AUTO_NAV_ENABLE ? 15 : ROTATE_ENABLE ? 20 : 25), .VISION_ENABLE(VISION_ENABLE), .ROTATE_ENABLE(ROTATE_ENABLE), .MISSION_ENABLE(MISSION_ENABLE), .AUTO_NAV_ENABLE(AUTO_NAV_ENABLE), .R4_ENABLE(AUTO_NAV_ENABLE), .REV5_ENABLE(REV5_ENABLE)
    ) u_bt_diag (
        .clk(clk_50m_i), .rst_n(key_s0_n_i), .sample_tick_i(sample_tick_d),
        .pid_p_i(pid_p),.pid_i_i(pid_i),.pid_d_i(pid_d),.pid_sequence_i(pid_sequence),.pid_status_i(pid_status),
        .wheel_targets_i(wheel_targets),.command_i(effective_command),.heading_locked_i(heading_locked),
        .heading_reference_i(heading_reference),.heading_error_i(heading_error),.heading_correction_i(heading_correction),.control_status_i(control_status),
        .wheel_fault_reason_i(wheel_fault_reason), .wheel_fault_speed_i(wheel_fault_speed),
        .wheel_fault_duty_i(wheel_fault_duty),
        .target_counts_i(effective_target_counts),
        .speed0_i(speed[0]), .speed1_i(speed[1]), .speed2_i(speed[2]), .speed3_i(speed[3]),
        .duty_gate_i(channel_enable),
        .duty0_i((REV5_ENABLE>=2 || channel_enable[0]) ? duty[0] : 16'sd0),
        .duty1_i((REV5_ENABLE>=2 || channel_enable[1]) ? duty[1] : 16'sd0),
        .duty2_i((REV5_ENABLE>=2 || channel_enable[2]) ? duty[2] : 16'sd0),
        .duty3_i((REV5_ENABLE>=2 || channel_enable[3]) ? duty[3] : 16'sd0),
        .fault_i(led_o[5]),
        .imu_valid_i(imu_angle_valid), .tof_valid_i(tof_valid[0]),
        .sensor_distance_i(tof0_distance_mm), .sensor_hard_stop_i(tof_hard_stop),
        .sensor_roll_i(imu_roll_raw), .sensor_pitch_i(imu_pitch_raw), .sensor_yaw_i(imu_yaw_raw),
        .sensor_fault_i(fault_flags), .sensor_wheel_fault_i(channel_fault),
        .vision_fresh_i(vision_fresh), .vision_visible_i(vision_visible),
        .vision_class_i(vision_class), .vision_lock_i(vision_lock),
        .vision_state_i(vision_state), .vision_active_i(vision_active),
        .turn_active_i(turn_active), .turn_sequence_i(turn_seq), .turn_state_i(turn_state),
        .turn_yaw_i(turn_yaw),.turn_target_i(turn_target_yaw),.turn_error_i(turn_error),
        .mission_active_i(mission_active),.mission_id_i(mission_id),.mission_class_i(mission_class),
        .mission_lock_i(mission_lock),.mission_state_i(mission_state),.mission_leg_i(mission_leg),
        .auto_active_i(auto_active),.auto_sequence_i(auto_sequence),.auto_state_i(auto_state | (auto_local ? 8'h80:8'h00)),.auto_reason_i(auto_reason),
        .auto_x_i(auto_x),.auto_y_i(auto_y),.auto_gx_i(auto_gx),.auto_gy_i(auto_gy),.auto_replans_i(auto_replans),.auto_ox_i(auto_ox),.auto_oy_i(auto_oy),
        .uart_tx_o(bt_uart_tx_o)
    );
endmodule

// Every SIN12 owner (manual, follow, mission, turn and navigation) crosses
// the same physical direction interlock. A changed wheel combination must
// first coast with PWM/IN disabled, reset the PI/kick state and restart the
// common start. Repeated heartbeats of the SAME command do not restart it.
// All upstream S0/ToF/fault shutdowns remain immediate through request_i.
module motor_direction_interlock #(parameter integer QUIET_CYCLES=5_000_000)(
    input wire clk,rst_n,request_i,input wire [2:0] command_i,
    output wire enable_o
);
    localparam integer WIDTH=QUIET_CYCLES<2 ? 1:$clog2(QUIET_CYCLES+1);
    reg [2:0] applied_command=0;
    reg [WIDTH-1:0] quiet_count=QUIET_CYCLES;
    wire changed=command_i!=applied_command;
    assign enable_o=request_i && command_i!=0 && (!changed || quiet_count>=QUIET_CYCLES);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin applied_command<=0;quiet_count<=QUIET_CYCLES;end
        else if (!request_i || command_i==0 || changed) begin
            if (quiet_count<QUIET_CYCLES)quiet_count<=quiet_count+1'b1;
            if (request_i && command_i!=0 && quiet_count>=QUIET_CYCLES)begin
                applied_command<=command_i;quiet_count<=0;
            end
        end else quiet_count<=0;
    end
endmodule

