// Real UART encoder/decoder, telemetry input ports only, no forced internals.
`timescale 1ns/1ps
module tb_sin12_r17_wait_telemetry;
reg clk=0;always #5 clk=~clk;reg rst=0;wire tx;wire[7:0] b;wire valid;
bt_combined_diag_uart #(.CLK_HZ(10000),.BAUD(1000),.TELEMETRY_DIV(1),.VISION_ENABLE(1),.ROTATE_ENABLE(1),.AUTO_NAV_ENABLE(1),.MISSION_ENABLE(1),.R4_ENABLE(1),.REV5_ENABLE(13)) dut(
.clk(clk),
.rst_n(rst),
.sample_tick_i(1'b1),
.target_counts_i(16'd0),
.speed0_i(16'd0),
.speed1_i(16'd0),
.speed2_i(16'd0),
.speed3_i(16'd0),
.duty0_i(16'd0),
.duty1_i(16'd0),
.duty2_i(16'd0),
.duty3_i(16'd0),
.duty_gate_i(4'd0),
.fault_i(1'd0),
.imu_valid_i(1'd0),
.tof_valid_i(1'd0),
.sensor_distance_i(16'd0),
.sensor_hard_stop_i(1'd0),
.sensor_roll_i(32'd0),
.sensor_pitch_i(32'd0),
.sensor_yaw_i(32'd0),
.sensor_fault_i(8'd0),
.sensor_wheel_fault_i(4'd0),
.vision_fresh_i(1'd0),
.vision_visible_i(1'd0),
.vision_active_i(1'd0),
.vision_class_i(16'd0),
.vision_lock_i(32'd0),
.vision_state_i(4'd0),
.turn_active_i(1'd0),
.turn_sequence_i(16'd0),
.turn_state_i(4'd0),
.turn_yaw_i(16'd0),
.turn_target_i(16'd0),
.turn_error_i(16'd0),
.mission_active_i(1'b1),
.mission_id_i(32'h8C3D63C2),
.mission_lock_i(32'd3),
.mission_class_i(16'd39),
.mission_state_i(5'd17),
.mission_leg_i(3'd0),
.wheel_fault_reason_i(12'd0),
.wheel_fault_speed_i(64'd0),
.wheel_fault_duty_i(64'd0),
.auto_active_i(1'd0),
.auto_sequence_i(16'd0),
.auto_state_i(8'd0),
.auto_reason_i(8'd0),
.auto_x_i(8'd0),
.auto_y_i(8'd0),
.auto_gx_i(8'd0),
.auto_gy_i(8'd0),
.auto_replans_i(8'd0),
.auto_ox_i(8'd0),
.auto_oy_i(8'd0),
.pid_p_i(6'd4),
.pid_i_i(6'd1),
.pid_d_i(6'd0),
.pid_sequence_i(16'd0),
.pid_status_i(2'd0),
.wheel_targets_i(64'd0),
.command_i(3'd0),
.heading_locked_i(1'd0),
.heading_reference_i(16'd0),
.heading_error_i(16'd0),
.heading_correction_i(8'd0),
.control_status_i(40'd0),.uart_tx_o(tx));
uart_rx #(.CLK_HZ(10000),.BAUD(1000)) monitor(.clk(clk),.rst_n(rst),.uart_rx_i(tx),.data_o(b),.data_valid_o(valid),.framing_error_o());
reg[8*80-1:0]linebuf=0;integer count=0,js=0,ks=0;
always @(negedge clk)if(valid)begin
 if(b==10)begin
   if(linebuf[8*(count-1)+:8]=="J")begin
     if(linebuf!={"J1 Q8C3D63C2 S11 C0027 K00000003 N0",8'h0d})$fatal(1,"J state16 truncated or identity torn %s",linebuf);
     js=js+1;
   end
   if(linebuf[8*(count-1)+:8]=="K")begin
     if(linebuf!={"K11000000040100",8'h0d})$fatal(1,"K11 not serialized %s",linebuf);ks=ks+1;
   end
   linebuf=0;count=0;
 end else begin linebuf={linebuf[8*79-1:0],b};count=count+1;end
end
initial begin repeat(5)@(negedge clk);rst=1;wait(js>=2 && ks>=2);
 $display("R17_REAL_UART_J_ACTIVE_S11_ORIGINAL_ID_AND_K11_PASS");$finish;end
initial begin #5000000;$fatal(1,"Timeout js=%d ks=%d",js,ks);end
endmodule
