`timescale 1ns/1ps
module tb_sin12_r5_control;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,rx=1;wire[3:0]pwm,in1,in2;wire[5:0]leds;
 acg720_motor_bt_drive #(.CLK_HZ(10000),.PWM_HZ(100),.BT_BAUD(1000),.DIAG_BAUD(1000),
  .STARTUP_MS(1),.STAGGER_MS(125),.KICK_MS(100),.BT_TIMEOUT_MS(1000),
  .AUTO_NAV_ENABLE(1),.AUTO_MAP_BITS({400{1'b1}}),.REV5_ENABLE(1),.ROTATE_ENABLE(1),
  .SENSOR_ENABLE(1),.TOF_HARD_STOP_MM(100),.DIAG_ENABLE(0)) dut(
  .clk_50m_i(clk),.key_s0_n_i(rst),.bt_uart_rx_i(rx),.pi_uart_rx_i(1'b1),
  .imu_uart_rx_i(1'b1),.tof0_uart_rx_i(1'b1),.encoder_a_i(4'd0),.encoder_b_i(4'd0),
  .motor_pwm_o(pwm),.motor_in1_o(in1),.motor_in2_o(in2),.led_o(leds),.diag_uart_tx_o(),.bt_uart_tx_o());
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task byte_tx(input[7:0]b);integer j;begin
  @(negedge clk);rx=0;clocks(10);
  for(j=0;j<8;j=j+1)begin rx=b[j];clocks(10);end
  rx=1;clocks(12);
 end endtask
 task still;begin
  force dut.wheels[0].directed_speed=17'sd0;force dut.wheels[1].directed_speed=17'sd0;
  force dut.wheels[2].directed_speed=17'sd0;force dut.wheels[3].directed_speed=17'sd0;
 end endtask
 task healthy;begin
  force dut.wheels[0].directed_speed=17'sd12;force dut.wheels[1].directed_speed=17'sd12;
  force dut.wheels[2].directed_speed=17'sd12;force dut.wheels[3].directed_speed=17'sd12;
 end endtask
 task binary_controls;begin
  byte_tx(8'haa);byte_tx(8'h55);byte_tx(3);byte_tx(8'h27);
  byte_tx(8'h66);byte_tx(0);byte_tx(6);byte_tx(0);
  byte_tx("U");byte_tx("A");byte_tx(0);byte_tx(0);byte_tx(0);byte_tx(0);
  byte_tx(0);byte_tx(0);
 end endtask
 integer k;
 // Check the stop-qualification simplification across owner transitions,
 // fault stops, UART cancellation, and local planner handoff.
 always @(negedge clk) if(rst && dut.ready && dut.g_trim.owner_stopped) begin
  if(dut.selected_command_raw!=0 || dut.channel_enable!=0)
   $fatal(1,"quiet qualification admitted a pending owner command or enabled wheel");
 end
 initial begin
  force dut.imu_angle_valid=1;force dut.heading_yaw_valid=1;force dut.turn_yaw=0;
  force dut.tof_valid=4'b0001;force dut.tof_hard_stop=0;
  force dut.tof_speed_scale_permille=10'd1000;force dut.tof0_distance_mm=16'd2000;force dut.tof_sample=0;
  still();clocks(5);rst=1;clocks(2200);
  if(pwm||in1||in2||dut.avoid_enabled)$fatal(1,"boot movement or avoidance auto-armed");
  byte_tx("S");byte_tx("1");clocks(1200);
  healthy();force dut.wheels[1].directed_speed=17'sd20;force dut.wheels[3].directed_speed=17'sd7;
  byte_tx("F");clocks(180);
  if(dut.channel_enable!=15 || !dut.wheels[0].u_control.kick_active)$fatal(1,"shared start/grace lost");
  if(dut.duty[1]>=dut.duty[3] || dut.duty[1]>=600 || dut.duty[3]<=600)
   $fatal(1,"fast/slow wheel did not receive DIFFERENT first-sample feedback: %d %d",dut.duty[1],dut.duty[3]);
  byte_tx("F");if(dut.channel_enable!=15)$fatal(1,"lease renewal interrupted shared start");
  byte_tx("S");still();clocks(3);if(pwm||in1||in2)$fatal(1,"S delayed by feedback pipeline");
  clocks(1200);healthy();force dut.wheels[1].directed_speed=17'sd0;
  byte_tx("F");clocks(1200);if(dut.channel_fault)$fatal(1,"loss protection fired before original grace/count");
  byte_tx("F");clocks(2100);
  if(dut.channel_fault!=2 || dut.wheel_fault_reason[5:3]!=1 || pwm||in1||in2)$fatal(1,"original M2 loss stop/evidence lost");
  byte_tx("U");if(dut.channel_fault!=2)$fatal(1,"U cleared a moving command");
  byte_tx("S");still();clocks(1000);byte_tx("U");
  if(dut.channel_fault!=2)$fatal(1,"U cleared before 250ms stable stop");
  clocks(1700);binary_controls();clocks(10);
  if(dut.channel_fault!=2 || dut.avoid_enabled)$fatal(1,"binary payload leaked U/A into control");
  byte_tx("U");clocks(10);
  if(dut.channel_fault || pwm||in1||in2)$fatal(1,"explicit blocked recovery failed fault%h pwm%h in%h/%h quiet%0d S%0d result%0d stopped%0d cmd%0d hard%0d severe%h",dut.channel_fault,pwm,in1,in2,dut.g_manual_safety.u_recovery.quiet,dut.g_manual_safety.u_recovery.stop_seen,dut.recovery_result,dut.g_manual_safety.u_recovery.stopped_i,dut.command,dut.tof_hard_stop,dut.severe_mask);
  healthy();force dut.wheels[1].directed_speed=17'sd60;byte_tx("F");clocks(1300);
  if(dut.channel_fault!=2 || dut.wheel_fault_reason[5:3]!=4)$fatal(1,"overspeed evidence lost");
  byte_tx("S");still();clocks(2700);byte_tx("U");clocks(3);
  if(dut.channel_fault!=2)$fatal(1,"U erased severe overspeed fault");
  rst=0;clocks(5);rst=1;clocks(2200);byte_tx("S");byte_tx("1");clocks(2700);
  byte_tx("A");clocks(3);if(!dut.avoid_enabled)$fatal(1,"stopped explicit avoidance arm failed");
  healthy();force dut.tof0_distance_mm=16'd350;byte_tx("F");clocks(150);
  force dut.tof_sample=1;clocks(1);force dut.tof_sample=0;still();clocks(10);
  if(!dut.avoid_capture || dut.channel_enable)$fatal(1,"near forward ray did not brake before handoff");
  for(k=0;k<4;k=k+1)begin byte_tx("F");clocks(700);end
  if(!dut.auto_active || !dut.auto_local)$fatal(1,"same FPGA planner did not accept local request; state %d reason %d",dut.auto_state,dut.auto_reason);
  if(dut.g_autonav.u_guard.occupied=={400{1'b1}})$fatal(1,"local mode incorrectly retained preset global map");
  byte_tx("S");clocks(5);
  if(dut.auto_active || dut.channel_enable || pwm||in1||in2)$fatal(1,"S failed to cancel ordinary avoidance");
  clocks(1200);if(dut.channel_enable)$fatal(1,"clearing obstacle automatically restarted old F");
  $display("R5_FIRST_SAMPLE_FEEDBACK_ORIGINAL_PROTECTION_EXPLICIT_RECOVERY_LOCAL_HANDOFF_UART_PASS");$finish;
 end
 initial begin #1500000;$fatal(1,"timeout");end
endmodule
