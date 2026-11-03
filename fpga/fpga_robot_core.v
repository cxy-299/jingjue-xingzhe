// Board-independent FPGA control core.
//
// The board wrapper only needs to provide:
//   * clk/rst and pi_uart_rx_i;
//   * tof_distance_mm_i/tof_valid_i from the selected ToF adapter;
//   * four encoder A/B inputs;
//   * four PWM and four direction outputs to the motor driver.
//
// ToF I2C/SPI and the final ACG720 .cst pin constraints deliberately remain
// outside this core because the sensor model and board pinout were not given.
module fpga_robot_core #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115200,
    parameter integer CONTROL_HZ = 100,
    parameter integer PWM_HZ = 20_000,
    // 默认超时与原系统一致；仿真可缩短，用于验证失联及旧视觉目标过期。
    parameter integer WATCHDOG_MS = 1500,
    parameter integer VISION_TIMEOUT_MS = 1500,
    // 四轮共用的初始速度环增益；KD 默认关闭，待实车测速后再调参。
    parameter integer WHEEL_KP = 4,
    parameter integer WHEEL_KI = 1,
    parameter integer WHEEL_KD = 0,
    parameter integer WHEEL_PID_SHIFT = 3,
    // Must be calibrated for the installed encoder, gear ratio and wheel.
    // Zero deliberately locks the motor outputs until calibration is done.
    parameter integer WHEEL_COUNTS_AT_FULL_SCALE = 0
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   pi_uart_rx_i,
    input  wire [15:0]            tof_distance_mm_i,
    input  wire                   tof_valid_i,
    input  wire                   estop_i,
    input  wire [3:0]             encoder_a_i,
    input  wire [3:0]             encoder_b_i,

    output wire [3:0]             motor_pwm_o,
    output wire [3:0]             motor_dir_o,
    output wire                   motor_enable_o,
    output wire                   link_alive_o,
    output wire                   vision_fresh_o,
    output wire                   target_valid_o,
    output wire                   target_confirmed_o,
    output wire                   safe_stop_o,
    output wire signed [15:0]     vx_cmd_o,
    output wire signed [15:0]     vy_cmd_o,
    output wire signed [15:0]     omega_cmd_o,
    output wire [3:0]             motion_state_o,
    output wire signed [15:0]     wheel_fl_ref_o,
    output wire signed [15:0]     wheel_fr_ref_o,
    output wire signed [15:0]     wheel_rl_ref_o,
    output wire signed [15:0]     wheel_rr_ref_o,
    output wire signed [15:0]     wheel_fl_speed_o,
    output wire signed [15:0]     wheel_fr_speed_o,
    output wire signed [15:0]     wheel_rl_speed_o,
    output wire signed [15:0]     wheel_rr_speed_o,
    output wire [15:0]            crc_error_count_o,
    output wire                   uart_framing_error_o
);
    localparam integer CONTROL_CYCLES = (CLK_HZ / CONTROL_HZ < 1) ? 1 : (CLK_HZ / CONTROL_HZ);
    reg [31:0] control_count;
    reg control_tick;
    reg pid_tick;

    wire target_centered_unused;
    wire [7:0] alignment_unused;
    wire [15:0] class_id_unused;
    wire [15:0] confidence_unused;
    wire [15:0] center_x_unused;
    wire [15:0] center_y_unused;
    wire [15:0] width_unused;
    wire [15:0] height_unused;
    wire signed [15:0] center_error;
    wire [15:0] area_ratio_unused;
    wire [31:0] frame_id_unused;
    wire [15:0] sequence_unused;
    wire vision_packet_pulse_unused;

    wire signed [15:0] omega_cmd;
    wire signed [15:0] wheel_fl_ref;
    wire signed [15:0] wheel_fr_ref;
    wire signed [15:0] wheel_rl_ref;
    wire signed [15:0] wheel_rr_ref;
    wire signed [15:0] wheel_fl_speed;
    wire signed [15:0] wheel_fr_speed;
    wire signed [15:0] wheel_rl_speed;
    wire signed [15:0] wheel_rr_speed;
    wire signed [15:0] wheel_fl_duty;
    wire signed [15:0] wheel_fr_duty;
    wire signed [15:0] wheel_rl_duty;
    wire signed [15:0] wheel_rr_duty;
    wire motion_safe_stop;
    wire drive_enable;
    wire hard_stop_now;
    wire safety_fault_now;
    wire drive_rearmed;
    wire signed [15:0] wheel_fl_target_counts;
    wire signed [15:0] wheel_fr_target_counts;
    wire signed [15:0] wheel_rl_target_counts;
    wire signed [15:0] wheel_rr_target_counts;

    function signed [15:0] to_encoder_counts;
        input signed [15:0] normalized_speed;
        reg signed [31:0] scaled;
        begin
            scaled = (normalized_speed * WHEEL_COUNTS_AT_FULL_SCALE) / 1000;
            if (scaled > 32767)
                scaled = 32767;
            else if (scaled < -32768)
                scaled = -32768;
            to_encoder_counts = scaled[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_count <= 32'd0;
            control_tick <= 1'b0;
            pid_tick <= 1'b0;
        end else begin
            // 编码器与策略在 control_tick 采样，下一拍 PID 才读取更新后的反馈/目标。
            // 避免同拍非阻塞赋值使 PID 使用上一整个控制周期的测速结果。
            pid_tick <= control_tick;
            if (control_count >= CONTROL_CYCLES - 1) begin
                control_count <= 32'd0;
                control_tick <= 1'b1;
            end else begin
                control_count <= control_count + 1'b1;
                control_tick <= 1'b0;
            end
        end
    end

    vision_uart_bridge #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD), .WATCHDOG_MS(WATCHDOG_MS),
        .VISION_TIMEOUT_MS(VISION_TIMEOUT_MS)
    ) u_vision_uart_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .pi_uart_rx_i(pi_uart_rx_i),
        .link_alive_o(link_alive_o),
        .vision_fresh_o(vision_fresh_o),
        .target_valid_o(target_valid_o),
        .target_confirmed_o(target_confirmed_o),
        .target_centered_o(target_centered_unused),
        .alignment_o(alignment_unused),
        .class_id_o(class_id_unused),
        .confidence_o(confidence_unused),
        .center_x_o(center_x_unused),
        .center_y_o(center_y_unused),
        .width_o(width_unused),
        .height_o(height_unused),
        .center_error_o(center_error),
        .area_ratio_o(area_ratio_unused),
        .frame_id_o(frame_id_unused),
        .sequence_o(sequence_unused),
        .crc_error_count_o(crc_error_count_o),
        .uart_framing_error_o(uart_framing_error_o),
        .vision_packet_pulse_o(vision_packet_pulse_unused),
        // 跟随核心暂不消费地图目标；导航预览顶层另接规划器，不能混称已集成导航。
        .nav_goal_pulse_o(), .nav_goal_x_o(), .nav_goal_y_o()
    );

    vision_motion_controller u_motion_controller (
        .clk(clk),
        .rst_n(rst_n),
        .control_tick_i(control_tick),
        .link_alive_i(link_alive_o && vision_fresh_o),
        .target_valid_i(target_valid_o),
        .target_confirmed_i(target_confirmed_o),
        .center_error_i(center_error),
        .tof_distance_mm_i(tof_distance_mm_i),
        .tof_valid_i(tof_valid_i),
        .estop_i(estop_i),
        .vx_cmd_o(vx_cmd_o),
        .vy_cmd_o(vy_cmd_o),
        .omega_cmd_o(omega_cmd),
        .state_o(motion_state_o),
        .safe_stop_o(motion_safe_stop)
    );

    assign omega_cmd_o = omega_cmd;
    assign hard_stop_now = tof_distance_mm_i <= 16'd250;
    // 策略状态每个控制周期才更新；这些异步故障必须立即反映在停车状态上。
    assign safety_fault_now = motion_safe_stop || hard_stop_now || !tof_valid_i ||
                              !link_alive_o || !vision_fresh_o || estop_i;
    drive_rearm_guard u_drive_rearm_guard (
        .clk(clk), .rst_n(rst_n), .control_tick_i(control_tick),
        .fault_i(safety_fault_now), .allow_o(drive_rearmed)
    );
    assign safe_stop_o = !drive_rearmed;
    assign drive_enable = drive_rearmed &&
                          (WHEEL_COUNTS_AT_FULL_SCALE > 0);
    assign motor_enable_o = drive_enable;

    mecanum_kinematics u_mecanum_kinematics (
        .vx_i(vx_cmd_o),
        .vy_i(vy_cmd_o),
        .omega_i(omega_cmd),
        .wheel_fl_o(wheel_fl_ref),
        .wheel_fr_o(wheel_fr_ref),
        .wheel_rl_o(wheel_rl_ref),
        .wheel_rr_o(wheel_rr_ref)
    );

    assign wheel_fl_ref_o = wheel_fl_ref;
    assign wheel_fr_ref_o = wheel_fr_ref;
    assign wheel_rl_ref_o = wheel_rl_ref;
    assign wheel_rr_ref_o = wheel_rr_ref;

    assign wheel_fl_target_counts = to_encoder_counts(wheel_fl_ref);
    assign wheel_fr_target_counts = to_encoder_counts(wheel_fr_ref);
    assign wheel_rl_target_counts = to_encoder_counts(wheel_rl_ref);
    assign wheel_rr_target_counts = to_encoder_counts(wheel_rr_ref);

    encoder_speed u_encoder_fl (
        .clk(clk), .rst_n(rst_n),
        .encoder_a_i(encoder_a_i[0]), .encoder_b_i(encoder_b_i[0]),
        .sample_tick_i(control_tick), .position_o(), .speed_o(wheel_fl_speed)
    );
    encoder_speed u_encoder_fr (
        .clk(clk), .rst_n(rst_n),
        .encoder_a_i(encoder_a_i[1]), .encoder_b_i(encoder_b_i[1]),
        .sample_tick_i(control_tick), .position_o(), .speed_o(wheel_fr_speed)
    );
    encoder_speed u_encoder_rl (
        .clk(clk), .rst_n(rst_n),
        .encoder_a_i(encoder_a_i[2]), .encoder_b_i(encoder_b_i[2]),
        .sample_tick_i(control_tick), .position_o(), .speed_o(wheel_rl_speed)
    );
    encoder_speed u_encoder_rr (
        .clk(clk), .rst_n(rst_n),
        .encoder_a_i(encoder_a_i[3]), .encoder_b_i(encoder_b_i[3]),
        .sample_tick_i(control_tick), .position_o(), .speed_o(wheel_rr_speed)
    );

    assign wheel_fl_speed_o = wheel_fl_speed;
    assign wheel_fr_speed_o = wheel_fr_speed;
    assign wheel_rl_speed_o = wheel_rl_speed;
    assign wheel_rr_speed_o = wheel_rr_speed;

    // 四个独立速度环：每轮编码器反馈只影响本轮 PWM，不交叉串扰。
    wheel_pi #(.KP(WHEEL_KP), .KI(WHEEL_KI), .KD(WHEEL_KD), .SHIFT(WHEEL_PID_SHIFT)) u_pi_fl (
        .clk(clk), .rst_n(rst_n), .control_tick_i(pid_tick),
        .enable_i(drive_enable), .target_speed_i(wheel_fl_target_counts),
        .feedback_speed_i(wheel_fl_speed), .duty_o(wheel_fl_duty)
    );
    wheel_pi #(.KP(WHEEL_KP), .KI(WHEEL_KI), .KD(WHEEL_KD), .SHIFT(WHEEL_PID_SHIFT)) u_pi_fr (
        .clk(clk), .rst_n(rst_n), .control_tick_i(pid_tick),
        .enable_i(drive_enable), .target_speed_i(wheel_fr_target_counts),
        .feedback_speed_i(wheel_fr_speed), .duty_o(wheel_fr_duty)
    );
    wheel_pi #(.KP(WHEEL_KP), .KI(WHEEL_KI), .KD(WHEEL_KD), .SHIFT(WHEEL_PID_SHIFT)) u_pi_rl (
        .clk(clk), .rst_n(rst_n), .control_tick_i(pid_tick),
        .enable_i(drive_enable), .target_speed_i(wheel_rl_target_counts),
        .feedback_speed_i(wheel_rl_speed), .duty_o(wheel_rl_duty)
    );
    wheel_pi #(.KP(WHEEL_KP), .KI(WHEEL_KI), .KD(WHEEL_KD), .SHIFT(WHEEL_PID_SHIFT)) u_pi_rr (
        .clk(clk), .rst_n(rst_n), .control_tick_i(pid_tick),
        .enable_i(drive_enable), .target_speed_i(wheel_rr_target_counts),
        .feedback_speed_i(wheel_rr_speed), .duty_o(wheel_rr_duty)
    );

    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm_fl (
        .clk(clk), .rst_n(rst_n), .enable_i(drive_enable), .duty_i(wheel_fl_duty),
        .pwm_o(motor_pwm_o[0]), .direction_o(motor_dir_o[0])
    );
    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm_fr (
        .clk(clk), .rst_n(rst_n), .enable_i(drive_enable), .duty_i(wheel_fr_duty),
        .pwm_o(motor_pwm_o[1]), .direction_o(motor_dir_o[1])
    );
    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm_rl (
        .clk(clk), .rst_n(rst_n), .enable_i(drive_enable), .duty_i(wheel_rl_duty),
        .pwm_o(motor_pwm_o[2]), .direction_o(motor_dir_o[2])
    );
    motor_pwm_dir #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ)) u_pwm_rr (
        .clk(clk), .rst_n(rst_n), .enable_i(drive_enable), .duty_i(wheel_rr_duty),
        .pwm_o(motor_pwm_o[3]), .direction_o(motor_dir_o[3])
    );
endmodule
