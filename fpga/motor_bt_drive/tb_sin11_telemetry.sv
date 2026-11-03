`timescale 1ns/1ps
module tb_sin11_telemetry;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg [7:0] count=0;
    wire tick=count==99;
    always @(posedge clk) count<=tick?0:count+1'b1;
    wire tx;wire [7:0] value;wire valid,error;
    string line="";integer motor_lines=0,sensor_lines=0,vision_lines=0,turn_lines=0,mission_lines=0;
    bt_combined_diag_uart #(.CLK_HZ(10000),.BAUD(1000),.TELEMETRY_DIV(1),.VISION_ENABLE(1),.ROTATE_ENABLE(1),.MISSION_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst),.sample_tick_i(tick),.target_counts_i(16'd12),
        .speed0_i(16'sd20),.speed1_i(16'sd21),.speed2_i(16'sd22),.speed3_i(16'sd23),
        .duty0_i(16'sd700),.duty1_i(16'sd701),.duty2_i(16'sd702),.duty3_i(16'sd703),
        .fault_i(1'b1),.wheel_fault_reason_i(12'h054),
        .wheel_fault_speed_i(64'h00000000FFFD0033),.wheel_fault_duty_i(64'h0000032002580320),
        .imu_valid_i(1'b1),.tof_valid_i(1'b1),.sensor_distance_i(16'd400),
        .sensor_hard_stop_i(1'b0),.sensor_roll_i(32'h3f800000),.sensor_pitch_i(32'h00000000),
        .sensor_yaw_i(32'h00000000),.sensor_fault_i(8'd0),.sensor_wheel_fault_i(4'd0),
        .vision_fresh_i(1'b1),.vision_visible_i(1'b1),.vision_active_i(1'b1),
        .vision_class_i(16'd39),.vision_lock_i(32'd42),.vision_state_i(4'd6),.turn_active_i(1'b1),.turn_sequence_i(16'h1234),.turn_state_i(4'd1),
        .turn_yaw_i(16'hff00),.turn_target_i(16'h3244),.turn_error_i(16'h3344),.mission_active_i(1'b1),.mission_id_i(32'h47534642),.mission_class_i(16'd39),.mission_lock_i(32'd42),.mission_state_i(4'd4),.mission_leg_i(3'd2),.uart_tx_o(tx));
    uart_rx #(.CLK_HZ(10000),.BAUD(1000)) rx(.clk(clk),.rst_n(rst),.uart_rx_i(tx),
        .data_o(value),.data_valid_o(valid),.framing_error_o(error));
    always @(posedge clk) if(valid) begin
        if(value==10) begin
            if(line=="M1 T012 A+020 D0700 F1 E4 X+051 P0800" || line=="M2 T012 A+021 D0701 F1 E2 X-003 P0600" ||
               line=="M3 T012 A+022 D0702 F1 E1 X+000 P0800" || line=="M4 T012 A+023 D0703 F1") motor_lines++;
            else if(line=="I1 T1 D0400 H0 F00 R3F800000 P00000000 Y00000000 W0") sensor_lines++;
            else if(line=="V1 L1 C0027 K0000002A S06 A1") vision_lines++;
            else if(line=="Z1 Q1234 S01 CFF00 T3244 E3344") turn_lines++;
            else if(line=="J1 Q47534642 S04 C0027 K0000002A N2")mission_lines++;
            else $fatal(1,"corrupt telemetry: %s",line);
            line="";
            if(motor_lines>=4 && sensor_lines>=4 && vision_lines>=4 && turn_lines>=4 && mission_lines>=4) begin
                $display("SIN11_FIVE_FRAME_UART_PASS");$finish;
            end
        end else if(value!=13) line={line,$sformatf("%c",value)};
    end
    initial begin repeat(5)@(negedge clk);rst=1;end
    initial begin #5000000;$fatal(1,"telemetry timeout");end
endmodule
