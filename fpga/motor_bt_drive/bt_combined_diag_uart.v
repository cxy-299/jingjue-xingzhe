// Combined 9600-baud Bluetooth telemetry: alternating motor and IMU/ToF frames.
module bt_combined_diag_uart #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9_600,
    parameter integer TARGET_COUNTS = 20,
    parameter integer TELEMETRY_DIV = 25,
    parameter integer VISION_ENABLE = 0,
    parameter integer AUTO_NAV_ENABLE = 0,
    parameter integer MISSION_ENABLE = 0,
    parameter integer ROTATE_ENABLE = 0,
    parameter integer R4_ENABLE = 0,
    parameter integer REV5_ENABLE = 0
) (
    input wire clk, input wire rst_n, input wire sample_tick_i,
    input wire [15:0] target_counts_i,
    input wire signed [15:0] speed0_i, speed1_i, speed2_i, speed3_i,
    input wire signed [15:0] duty0_i, duty1_i, duty2_i, duty3_i,
    input wire [3:0] duty_gate_i,
    input wire fault_i,
    input wire imu_valid_i, tof_valid_i, input wire [15:0] sensor_distance_i,
    input wire sensor_hard_stop_i, input wire [31:0] sensor_roll_i,
    input wire [31:0] sensor_pitch_i, sensor_yaw_i,
    input wire [7:0] sensor_fault_i, input wire [3:0] sensor_wheel_fault_i,
    input wire vision_fresh_i, vision_visible_i, vision_active_i,
    input wire [15:0] vision_class_i, input wire [31:0] vision_lock_i,
    input wire [3:0] vision_state_i,
    input wire turn_active_i,
    input wire [15:0] turn_sequence_i,
    input wire [3:0] turn_state_i,
    input wire [15:0] turn_yaw_i,turn_target_i,turn_error_i,
    input wire mission_active_i,input wire [31:0] mission_id_i,mission_lock_i,
    input wire [15:0] mission_class_i,input wire [4:0] mission_state_i,
    input wire [2:0] mission_leg_i,
    input wire [11:0] wheel_fault_reason_i,
    input wire [63:0] wheel_fault_speed_i, wheel_fault_duty_i,
    input wire auto_active_i,
    input wire [15:0] auto_sequence_i,
    input wire [7:0] auto_state_i,auto_reason_i,auto_x_i,auto_y_i,auto_gx_i,auto_gy_i,auto_replans_i,auto_ox_i,auto_oy_i,
    input wire [5:0] pid_p_i,pid_i_i,pid_d_i,
    input wire [15:0] pid_sequence_i,input wire [1:0] pid_status_i,
    input wire [63:0] wheel_targets_i,input wire [2:0] command_i,
    input wire heading_locked_i,input wire [15:0] heading_reference_i,heading_error_i,
    input wire [7:0] heading_correction_i,
    input wire [39:0] control_status_i,
    output wire uart_tx_o
);
    localparam integer MAX_TARGET = TARGET_COUNTS > 999 ? 999 : TARGET_COUNTS;
    // All four wheels latch at one 10 ms epoch, frozen again for UART serialization.
    reg [15:0] sample_sequence=0;
    reg [223:0] common_raw_sample=0,c_hold=0;
    reg [3:0] common_gate=0;
    // Capture raw PID duties and physical enables at the SAME epoch. Apply
    // the enable masks only AFTER that register boundary, before UART hold.
    wire [223:0] common_sample=REV5_ENABLE>=2 ? {common_raw_sample[223:64],
        common_gate[0]?common_raw_sample[63:48]:16'd0,
        common_gate[1]?common_raw_sample[47:32]:16'd0,
        common_gate[2]?common_raw_sample[31:16]:16'd0,
        common_gate[3]?common_raw_sample[15:0]:16'd0}:common_raw_sample;
    reg [55:0] k_hold=0;
    reg [39:0] o_hold=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin sample_sequence<=0;common_raw_sample<=0;common_gate<=0;end
        else if(sample_tick_i)begin
            sample_sequence<=sample_sequence+1'b1;
            common_gate<=duty_gate_i;
            common_raw_sample<={sample_sequence,4'd0,heading_locked_i,command_i,
                heading_reference_i,heading_error_i,heading_correction_i,
                wheel_targets_i[7:0],wheel_targets_i[23:16],wheel_targets_i[39:32],wheel_targets_i[55:48],
                speed0_i,speed1_i,speed2_i,speed3_i,duty0_i,duty1_i,duty2_i,duty3_i};
        end
    end
    reg [7:0] tick_count = 0;
    reg frame_pending = 0;
    reg [3:0] frame_kind = 0; // R5 adds O control/blocked-state readback.
    reg [1:0] next_wheel = 0;
    reg [1:0] wheel_hold = 0;
    reg [9:0] actual_hold = 0, duty_hold = 0, target_hold = MAX_TARGET;
    reg negative_hold = 0, fault_hold = 0;
    reg [2:0] reason_hold = 0;
    reg [9:0] trip_abs_hold = 0, trip_duty_hold = 0;
    reg trip_negative_hold = 0;
    wire signed [15:0] trip_speed = wheel_fault_speed_i[next_wheel*16 +: 16];
    wire signed [16:0] trip_abs = trip_speed < 0 ? -$signed(trip_speed) : $signed(trip_speed);
    wire [15:0] trip_duty = wheel_fault_duty_i[next_wheel*16 +: 16];
    reg sensor_imu_hold = 0, sensor_tof_hold = 0, sensor_hard_hold = 1;
    reg [15:0] sensor_distance_hold = 0;
    reg [31:0] sensor_roll_hold = 0, sensor_pitch_hold = 0, sensor_yaw_hold = 0;
    reg [7:0] sensor_fault_hold = 0;
    reg [3:0] sensor_wheel_fault_hold = 0;
    reg v_fresh=0, v_visible=0, v_active=0;
    reg [15:0] v_class=16'hffff;
    reg [31:0] v_lock=0;
    reg [3:0] v_state=0;
    reg j_active=0;reg [31:0] j_id=0,j_lock=0;
    reg [15:0] j_class=0;reg [4:0] j_state=0;reg [2:0] j_leg=0;
    reg n_active=0;
    reg [15:0] n_seq=0;
    reg [7:0] n_state=0,n_reason=0,n_x=0,n_y=0,n_gx=0,n_gy=0,n_replans=0,n_ox=255,n_oy=255;
    reg z_active=0;
    reg [15:0] z_sequence=0,z_yaw=0,z_target=0,z_error=0;
    reg [3:0] z_state=0;
    reg [5:0] byte_index = 0;
    reg [1:0] state = 0;
    reg [7:0] tx_byte = 0, tx_start = 0;
    wire tx_busy, tx_done;
    reg signed [15:0] selected_speed, selected_duty;
    reg signed [15:0] selected_speed_pipe=0,selected_duty_pipe=0;
    reg selected_gate_pipe=0;
    wire signed [16:0] selected_abs = selected_speed_pipe < 0 ? -$signed(selected_speed_pipe) : $signed(selected_speed_pipe);
    wire [9:0] actual_hundreds = actual_hold / 100;
    wire [9:0] duty_thousands = duty_hold / 1000;

    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin hex_ascii = nibble < 10 ? 8'h30 + nibble : 8'h41 + nibble - 4'd10; end
    endfunction

    always @* begin
        case (next_wheel)
            0: begin selected_speed = speed0_i; selected_duty = duty0_i; end
            1: begin selected_speed = speed1_i; selected_duty = duty1_i; end
            2: begin selected_speed = speed2_i; selected_duty = duty2_i; end
            default: begin selected_speed = speed3_i; selected_duty = duty3_i; end
        endcase
    end

    uart_tx_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk), .rst_n(rst_n), .start_i(tx_start[0]), .data_i(tx_byte),
        .tx_o(uart_tx_o), .busy_o(tx_busy), .done_o(tx_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selected_speed_pipe<=0;selected_duty_pipe<=0;selected_gate_pipe<=0;c_hold<=0;k_hold<=0;
            v_fresh<=0; v_visible<=0; v_active<=0; v_class<=16'hffff; v_lock<=0; v_state<=0;
            j_active<=0;j_id<=0;j_lock<=0;j_class<=0;j_state<=0;j_leg<=0;
            n_active<=0;n_seq<=0;n_state<=0;n_reason<=0;n_x<=0;n_y<=0;n_gx<=0;n_gy<=0;n_replans<=0;n_ox<=255;n_oy<=255;
            z_active<=0;z_sequence<=0;z_yaw<=0;z_target<=0;z_error<=0;z_state<=0;
            tick_count <= 0; frame_pending <= 0; frame_kind <= 0; next_wheel <= 0;
            state <= 0; byte_index <= 0; tx_byte <= 0; tx_start <= 0;
            wheel_hold <= 0; actual_hold <= 0; duty_hold <= 0; target_hold <= MAX_TARGET;
            negative_hold <= 0; fault_hold <= 0;
            reason_hold <= 0; trip_abs_hold <= 0; trip_duty_hold <= 0; trip_negative_hold <= 0;
            sensor_imu_hold <= 0; sensor_tof_hold <= 0; sensor_hard_hold <= 1;
            sensor_distance_hold <= 0; sensor_roll_hold <= 0; sensor_pitch_hold <= 0; sensor_yaw_hold <= 0;
            sensor_fault_hold <= 0; sensor_wheel_fault_hold <= 0;
        end else begin
            // Snapshot the selected wheel before absolute-value/decimal formatting.
            // This breaks the navigation direction -> speed sign -> abs timing
            // path. next_wheel stays stable for the whole preceding UART frame.
            selected_speed_pipe<=selected_speed;selected_duty_pipe<=selected_duty;selected_gate_pipe<=duty_gate_i[next_wheel];
            tx_start <= 0;
            if (sample_tick_i) begin
                if (tick_count >= TELEMETRY_DIV - 1) begin
                    tick_count <= 0;
                    if (state == 0) frame_pending <= 1;
                end else tick_count <= tick_count + 1'b1;
            end
            case (state)
                0: if (frame_pending) begin
                    frame_pending <= 0; byte_index <= 0; state <= 1;
                    if(frame_kind==8)begin o_hold<=control_status_i;
                    end else if(frame_kind==7)begin
                        k_hold<={REV5_ENABLE>=16?8'h14:REV5_ENABLE>=15?8'h13:REV5_ENABLE>=14?8'h12:REV5_ENABLE>=13?8'h11:REV5_ENABLE>=12?8'h10:REV5_ENABLE>=11?8'h0F:REV5_ENABLE>=10?8'h0E:REV5_ENABLE>=8?8'h0C:REV5_ENABLE>=7?8'h0B:REV5_ENABLE>=6?8'h0A:REV5_ENABLE>=5?8'h09:REV5_ENABLE>=4?8'h08:REV5_ENABLE>=3?8'h07:REV5_ENABLE>=2?8'h06:REV5_ENABLE?8'h05:8'h04,pid_sequence_i,6'd0,pid_status_i,2'd0,pid_p_i,2'd0,pid_i_i,2'd0,pid_d_i};
                    end else if(frame_kind==6)begin c_hold<=common_sample;
                    end else if(frame_kind==5)begin
                        n_active<=auto_active_i;n_seq<=auto_sequence_i;n_state<=auto_state_i;n_reason<=auto_reason_i;
                        n_x<=auto_x_i;n_y<=auto_y_i;n_gx<=auto_gx_i;n_gy<=auto_gy_i;n_replans<=auto_replans_i;n_ox<=auto_ox_i;n_oy<=auto_oy_i;
                    end else if(frame_kind==4)begin
                        j_active<=mission_active_i;j_id<=mission_id_i;j_class<=mission_class_i;
                        j_lock<=mission_lock_i;j_state<=mission_state_i;j_leg<=mission_leg_i;
                    end else if(frame_kind==3)begin
                        z_active<=turn_active_i;z_sequence<=turn_sequence_i;z_state<=turn_state_i;
                        z_yaw<=turn_yaw_i;z_target<=turn_target_i;z_error<=turn_error_i;
                    end else if (frame_kind==2) begin
                        v_fresh<=vision_fresh_i; v_visible<=vision_visible_i;
                        v_active<=vision_active_i; v_class<=vision_class_i;
                        v_lock<=vision_lock_i; v_state<=vision_state_i;
                    end else if (frame_kind==1) begin
                        sensor_imu_hold <= imu_valid_i; sensor_tof_hold <= tof_valid_i;
                        sensor_hard_hold <= sensor_hard_stop_i; sensor_distance_hold <= sensor_distance_i;
                        sensor_roll_hold <= sensor_roll_i; sensor_pitch_hold <= sensor_pitch_i; sensor_yaw_hold <= sensor_yaw_i;
                        sensor_fault_hold <= sensor_fault_i; sensor_wheel_fault_hold <= sensor_wheel_fault_i;
                    end else begin
                        wheel_hold <= next_wheel; next_wheel <= next_wheel + 1'b1;
                        actual_hold <= selected_abs > 999 ? 999 : selected_abs[9:0];
                        negative_hold <= selected_speed_pipe < 0;
                        duty_hold <= (REV5_ENABLE>=2 && !selected_gate_pipe) ? 0 : selected_duty_pipe > 1000 ? 1000 : selected_duty_pipe[9:0];
                        fault_hold <= fault_i;
                        target_hold <= R4_ENABLE ? wheel_targets_i[next_wheel*16+:16] : target_counts_i > 999 ? 999 : target_counts_i[9:0];
                        reason_hold <= MISSION_ENABLE ? wheel_fault_reason_i[next_wheel*3 +: 3] : 3'd0;
                        trip_abs_hold <= trip_abs > 999 ? 10'd999 : trip_abs[9:0];
                        trip_negative_hold <= trip_speed < 0;
                        trip_duty_hold <= trip_duty > 1000 ? 10'd1000 : trip_duty[9:0];
                    end
                end
                1: if (!tx_busy) begin
                    if(frame_kind==8)begin
                        if(byte_index==0)tx_byte<="O";
                        else if(byte_index<=10)tx_byte<=hex_ascii(o_hold[39-(byte_index-1)*4 -: 4]);
                        else tx_byte<=byte_index==11 ? 8'h0d:8'h0a;
                    end else if(frame_kind==7)begin
                        if(byte_index==0)tx_byte<="K";
                        else if(byte_index<=14)tx_byte<=hex_ascii(k_hold[55-(byte_index-1)*4 -: 4]);
                        else tx_byte<=byte_index==15 ? 8'h0d : 8'h0a;
                    end else if(frame_kind==6)begin
                        if(byte_index==0)tx_byte<="C";
                        else if(byte_index<=56)tx_byte<=hex_ascii(c_hold[223-(byte_index-1)*4 -: 4]);
                        else tx_byte<=byte_index==57 ? 8'h0d : 8'h0a;
                    end else if(frame_kind==5)begin
                        case(byte_index)
                            0:tx_byte<="N";
                            1:tx_byte<=n_active ? "1":"0";
                            2:tx_byte<=" ";
                            3:tx_byte<="Q";
                            4:tx_byte<=hex_ascii(n_seq[15:12]);
                            5:tx_byte<=hex_ascii(n_seq[11:8]);
                            6:tx_byte<=hex_ascii(n_seq[7:4]);
                            7:tx_byte<=hex_ascii(n_seq[3:0]);
                            8:tx_byte<=" ";
                            9:tx_byte<="S";
                            10:tx_byte<=hex_ascii(n_state[7:4]);
                            11:tx_byte<=hex_ascii(n_state[3:0]);
                            12:tx_byte<=" ";
                            13:tx_byte<="E";
                            14:tx_byte<=hex_ascii(n_reason[7:4]);
                            15:tx_byte<=hex_ascii(n_reason[3:0]);
                            16:tx_byte<=" ";
                            17:tx_byte<="X";
                            18:tx_byte<=hex_ascii(n_x[7:4]);
                            19:tx_byte<=hex_ascii(n_x[3:0]);
                            20:tx_byte<=" ";
                            21:tx_byte<="Y";
                            22:tx_byte<=hex_ascii(n_y[7:4]);
                            23:tx_byte<=hex_ascii(n_y[3:0]);
                            24:tx_byte<=" ";
                            25:tx_byte<="G";
                            26:tx_byte<=hex_ascii(n_gx[7:4]);
                            27:tx_byte<=hex_ascii(n_gx[3:0]);
                            28:tx_byte<=" ";
                            29:tx_byte<="H";
                            30:tx_byte<=hex_ascii(n_gy[7:4]);
                            31:tx_byte<=hex_ascii(n_gy[3:0]);
                            32:tx_byte<=" ";
                            33:tx_byte<="R";
                            34:tx_byte<=hex_ascii(n_replans[7:4]);
                            35:tx_byte<=hex_ascii(n_replans[3:0]);
                            36:tx_byte<=" ";37:tx_byte<="O";
                            38:tx_byte<=hex_ascii(n_ox[7:4]);39:tx_byte<=hex_ascii(n_ox[3:0]);
                            40:tx_byte<=" ";41:tx_byte<="P";
                            42:tx_byte<=hex_ascii(n_oy[7:4]);43:tx_byte<=hex_ascii(n_oy[3:0]);
                            44:tx_byte<=8'h0d;45:tx_byte<=8'h0a;
                        endcase
                    end else if(frame_kind==4)begin
                        case(byte_index)
                            0:tx_byte<=8'h4a;
                            1:tx_byte<=j_active?"1":"0";
                            2:tx_byte<=8'h20;
                            3:tx_byte<=8'h51;
                            4:tx_byte<=hex_ascii(j_id[31:28]);
                            5:tx_byte<=hex_ascii(j_id[27:24]);
                            6:tx_byte<=hex_ascii(j_id[23:20]);
                            7:tx_byte<=hex_ascii(j_id[19:16]);
                            8:tx_byte<=hex_ascii(j_id[15:12]);
                            9:tx_byte<=hex_ascii(j_id[11:8]);
                            10:tx_byte<=hex_ascii(j_id[7:4]);
                            11:tx_byte<=hex_ascii(j_id[3:0]);
                            12:tx_byte<=8'h20;
                            13:tx_byte<=8'h53;
                            14:tx_byte<=hex_ascii({3'b0,j_state[4]});
                            15:tx_byte<=hex_ascii(j_state[3:0]);
                            16:tx_byte<=8'h20;
                            17:tx_byte<=8'h43;
                            18:tx_byte<=hex_ascii(j_class[15:12]);
                            19:tx_byte<=hex_ascii(j_class[11:8]);
                            20:tx_byte<=hex_ascii(j_class[7:4]);
                            21:tx_byte<=hex_ascii(j_class[3:0]);
                            22:tx_byte<=8'h20;
                            23:tx_byte<=8'h4b;
                            24:tx_byte<=hex_ascii(j_lock[31:28]);
                            25:tx_byte<=hex_ascii(j_lock[27:24]);
                            26:tx_byte<=hex_ascii(j_lock[23:20]);
                            27:tx_byte<=hex_ascii(j_lock[19:16]);
                            28:tx_byte<=hex_ascii(j_lock[15:12]);
                            29:tx_byte<=hex_ascii(j_lock[11:8]);
                            30:tx_byte<=hex_ascii(j_lock[7:4]);
                            31:tx_byte<=hex_ascii(j_lock[3:0]);
                            32:tx_byte<=8'h20;
                            33:tx_byte<=8'h4e;
                            34:tx_byte<=8'h30+{5'd0,j_leg};
                            35:tx_byte<=8'h0d;
                            36:tx_byte<=8'h0a;
                            default:tx_byte<=8'h0a;
                        endcase
                    end else if(frame_kind==3)begin
                        case(byte_index)
                            0:tx_byte<="Z";1:tx_byte<=z_active?"1":"0";
                            2:tx_byte<=" ";3:tx_byte<="Q";
                            4:tx_byte<=hex_ascii(z_sequence[15:12]);5:tx_byte<=hex_ascii(z_sequence[11:8]);
                            6:tx_byte<=hex_ascii(z_sequence[7:4]);7:tx_byte<=hex_ascii(z_sequence[3:0]);
                            8:tx_byte<=" ";9:tx_byte<="S";10:tx_byte<="0";11:tx_byte<=hex_ascii(z_state);
                            12:tx_byte<=" ";13:tx_byte<="C";
                            14:tx_byte<=hex_ascii(z_yaw[15:12]);15:tx_byte<=hex_ascii(z_yaw[11:8]);
                            16:tx_byte<=hex_ascii(z_yaw[7:4]);17:tx_byte<=hex_ascii(z_yaw[3:0]);
                            18:tx_byte<=" ";19:tx_byte<="T";
                            20:tx_byte<=hex_ascii(z_target[15:12]);21:tx_byte<=hex_ascii(z_target[11:8]);
                            22:tx_byte<=hex_ascii(z_target[7:4]);23:tx_byte<=hex_ascii(z_target[3:0]);
                            24:tx_byte<=" ";25:tx_byte<="E";
                            26:tx_byte<=hex_ascii(z_error[15:12]);27:tx_byte<=hex_ascii(z_error[11:8]);
                            28:tx_byte<=hex_ascii(z_error[7:4]);29:tx_byte<=hex_ascii(z_error[3:0]);
                            30:tx_byte<=8'h0d;default:tx_byte<=8'h0a;
                        endcase
                    end else if (frame_kind==2) begin
                        case(byte_index)
                            0: tx_byte<="V"; 1: tx_byte<=v_fresh?"1":"0";
                            2: tx_byte<=" "; 3: tx_byte<="L"; 4: tx_byte<=v_visible?"1":"0";
                            5: tx_byte<=" "; 6: tx_byte<="C";
                            7: tx_byte<=hex_ascii(v_class[15:12]); 8: tx_byte<=hex_ascii(v_class[11:8]);
                            9: tx_byte<=hex_ascii(v_class[7:4]); 10: tx_byte<=hex_ascii(v_class[3:0]);
                            11: tx_byte<=" "; 12: tx_byte<="K";
                            13: tx_byte<=hex_ascii(v_lock[31:28]); 14: tx_byte<=hex_ascii(v_lock[27:24]);
                            15: tx_byte<=hex_ascii(v_lock[23:20]); 16: tx_byte<=hex_ascii(v_lock[19:16]);
                            17: tx_byte<=hex_ascii(v_lock[15:12]); 18: tx_byte<=hex_ascii(v_lock[11:8]);
                            19: tx_byte<=hex_ascii(v_lock[7:4]); 20: tx_byte<=hex_ascii(v_lock[3:0]);
                            21: tx_byte<=" "; 22: tx_byte<="S"; 23: tx_byte<="0"; 24: tx_byte<=hex_ascii(v_state);
                            25: tx_byte<=" "; 26: tx_byte<="A"; 27: tx_byte<=v_active?"1":"0";
                            28: tx_byte<=8'h0d; default: tx_byte<=8'h0a;
                        endcase
                    end else if (frame_kind==1) begin
                        case (byte_index)
                            0: tx_byte <= "I"; 1: tx_byte <= sensor_imu_hold ? "1" : "0"; 2: tx_byte <= " "; 3: tx_byte <= "T"; 4: tx_byte <= sensor_tof_hold ? "1" : "0";
                            5: tx_byte <= " "; 6: tx_byte <= "D"; 7: tx_byte <= 8'h30 + ((sensor_distance_hold/1000)%10); 8: tx_byte <= 8'h30 + ((sensor_distance_hold/100)%10); 9: tx_byte <= 8'h30 + ((sensor_distance_hold/10)%10); 10: tx_byte <= 8'h30 + sensor_distance_hold%10;
                            11: tx_byte <= " "; 12: tx_byte <= "H"; 13: tx_byte <= sensor_hard_hold ? "1" : "0"; 14: tx_byte <= " "; 15: tx_byte <= "F"; 16: tx_byte <= hex_ascii(sensor_fault_hold[7:4]); 17: tx_byte <= hex_ascii(sensor_fault_hold[3:0]); 18: tx_byte <= " "; 19: tx_byte <= "R";
                            20: tx_byte <= hex_ascii(sensor_roll_hold[31:28]); 21: tx_byte <= hex_ascii(sensor_roll_hold[27:24]); 22: tx_byte <= hex_ascii(sensor_roll_hold[23:20]); 23: tx_byte <= hex_ascii(sensor_roll_hold[19:16]); 24: tx_byte <= hex_ascii(sensor_roll_hold[15:12]); 25: tx_byte <= hex_ascii(sensor_roll_hold[11:8]); 26: tx_byte <= hex_ascii(sensor_roll_hold[7:4]); 27: tx_byte <= hex_ascii(sensor_roll_hold[3:0]);
                            28: tx_byte <= " "; 29: tx_byte <= "P"; 30: tx_byte <= hex_ascii(sensor_pitch_hold[31:28]); 31: tx_byte <= hex_ascii(sensor_pitch_hold[27:24]); 32: tx_byte <= hex_ascii(sensor_pitch_hold[23:20]); 33: tx_byte <= hex_ascii(sensor_pitch_hold[19:16]); 34: tx_byte <= hex_ascii(sensor_pitch_hold[15:12]); 35: tx_byte <= hex_ascii(sensor_pitch_hold[11:8]); 36: tx_byte <= hex_ascii(sensor_pitch_hold[7:4]); 37: tx_byte <= hex_ascii(sensor_pitch_hold[3:0]);
                            38: tx_byte <= " "; 39: tx_byte <= "Y"; 40: tx_byte <= hex_ascii(sensor_yaw_hold[31:28]); 41: tx_byte <= hex_ascii(sensor_yaw_hold[27:24]); 42: tx_byte <= hex_ascii(sensor_yaw_hold[23:20]); 43: tx_byte <= hex_ascii(sensor_yaw_hold[19:16]); 44: tx_byte <= hex_ascii(sensor_yaw_hold[15:12]); 45: tx_byte <= hex_ascii(sensor_yaw_hold[11:8]); 46: tx_byte <= hex_ascii(sensor_yaw_hold[7:4]); 47: tx_byte <= hex_ascii(sensor_yaw_hold[3:0]);
                            48: tx_byte <= " "; 49: tx_byte <= "W"; 50: tx_byte <= hex_ascii(sensor_wheel_fault_hold); 51: tx_byte <= 8'h0d; default: tx_byte <= 8'h0a;
                        endcase
                    end else begin
                        case (byte_index)
                            0: tx_byte <= "M"; 1: tx_byte <= 8'h31 + {6'd0,wheel_hold}; 2: tx_byte <= " "; 3: tx_byte <= "T";
                            4: tx_byte <= 8'h30 + (target_hold/100)%10; 5: tx_byte <= 8'h30 + (target_hold/10)%10; 6: tx_byte <= 8'h30 + target_hold%10; 7: tx_byte <= " "; 8: tx_byte <= "A"; 9: tx_byte <= negative_hold ? "-" : "+";
                            10: tx_byte <= 8'h30 + actual_hundreds[3:0]; 11: tx_byte <= 8'h30 + (actual_hold/10)%10; 12: tx_byte <= 8'h30 + actual_hold%10; 13: tx_byte <= " "; 14: tx_byte <= "D";
                            15: tx_byte <= 8'h30 + duty_thousands[3:0]; 16: tx_byte <= 8'h30 + (duty_hold/100)%10; 17: tx_byte <= 8'h30 + (duty_hold/10)%10; 18: tx_byte <= 8'h30 + duty_hold%10; 19: tx_byte <= " "; 20: tx_byte <= "F"; 21: tx_byte <= fault_hold ? "1" : "0";
                            22: tx_byte <= reason_hold != 0 ? " " : 8'h0d;
                            23: tx_byte <= reason_hold != 0 ? "E" : 8'h0a;
                            24: tx_byte <= hex_ascii({1'b0,reason_hold});
                            25: tx_byte <= " "; 26: tx_byte <= "X";
                            27: tx_byte <= trip_negative_hold ? "-" : "+";
                            28: tx_byte <= 8'h30 + (trip_abs_hold/100)%10;
                            29: tx_byte <= 8'h30 + (trip_abs_hold/10)%10;
                            30: tx_byte <= 8'h30 + trip_abs_hold%10;
                            31: tx_byte <= " "; 32: tx_byte <= "P";
                            33: tx_byte <= 8'h30 + (trip_duty_hold/1000)%10;
                            34: tx_byte <= 8'h30 + (trip_duty_hold/100)%10;
                            35: tx_byte <= 8'h30 + (trip_duty_hold/10)%10;
                            36: tx_byte <= 8'h30 + trip_duty_hold%10;
                            37: tx_byte <= 8'h0d; default: tx_byte <= 8'h0a;
                        endcase
                    end
                    tx_start[0] <= 1; state <= 2;
                end
                2: if (tx_done) begin
                    if ((frame_kind==1 && byte_index==52) || (frame_kind==0 && byte_index==(reason_hold != 0 ? 38 : 23)) || (frame_kind==2 && byte_index==29) || (frame_kind==3 && byte_index==31) || (frame_kind==4 && byte_index==36) || (frame_kind==5 && byte_index==45) || (frame_kind==6 && byte_index==58) || (frame_kind==7 && byte_index==16) || (frame_kind==8 && byte_index==12)) begin
                        frame_kind <= frame_kind==0 ? 1 :
                            (frame_kind==1 && VISION_ENABLE) ? 2 :
                            ((frame_kind==1 || frame_kind==2) && ROTATE_ENABLE) ? 3 :
                            (frame_kind==3 && MISSION_ENABLE) ? 4 :
                            (frame_kind==4 && AUTO_NAV_ENABLE) ? 5 :
                            (frame_kind==5 && R4_ENABLE) ? 6 :
                            (frame_kind==6 && R4_ENABLE) ? 7 :
                            (frame_kind==7 && REV5_ENABLE) ? 8 : 0;
                        state<=0; end
                    else begin byte_index <= byte_index + 1'b1; state <= 1; end
                end
            endcase
        end
    end
endmodule
