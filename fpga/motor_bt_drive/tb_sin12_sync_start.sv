`timescale 1ns/1ps
// Real UART/control/PWM integration; modeled healthy encoder counts, not a
// traction/current model. STAGGER_MS deliberately nonzero to catch regressions.
module tb_sin12_sync_start;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,rx=1;wire[3:0] pwm,in1,in2;wire[5:0] leds;
 acg720_motor_bt_drive #(.CLK_HZ(10000),.PWM_HZ(100),.BT_BAUD(1000),.DIAG_BAUD(1000),
  .STARTUP_MS(1),.STAGGER_MS(125),.KICK_MS(100),.AUTO_NAV_ENABLE(1),
  .SENSOR_ENABLE(1),.TOF_HARD_STOP_MM(100),.DIAG_ENABLE(0)) dut(
  .clk_50m_i(clk),.key_s0_n_i(rst),.bt_uart_rx_i(rx),.pi_uart_rx_i(1'b1),
  .imu_uart_rx_i(1'b1),.tof0_uart_rx_i(1'b1),.encoder_a_i(4'b0),.encoder_b_i(4'b0),
  .motor_pwm_o(pwm),.motor_in1_o(in1),.motor_in2_o(in2),.led_o(leds),
  .diag_uart_tx_o(),.bt_uart_tx_o());
 integer starts=0,last_kick=600;reg last_enable=0;
 always @(negedge clk) if(rst && dut.ready)begin
  if(dut.channel_enable!==4'b0 && dut.channel_enable!==4'b1111)
   $fatal(1,"partial wheel enable: %b",dut.channel_enable);
  if(dut.channel_enable==4'b1111)begin
   if(!last_enable)begin
    starts=starts+1;last_kick=600;
    if(dut.effective_target_counts>0 && (dut.duty[0]<600 || dut.duty[0]>650))
     $fatal(1,"full-duty startup returned");
   end
   if(dut.wheels[0].u_control.kick_active && dut.effective_target_counts>0)begin
    if(dut.duty[0]!=dut.duty[1] || dut.duty[0]!=dut.duty[2] || dut.duty[0]!=dut.duty[3])
     $fatal(1,"kick is not simultaneous");
    if(dut.duty[0]>850 || dut.duty[0]<600 || dut.duty[0]>last_kick+50)
     $fatal(1,"kick ceiling/slew violated: %d -> %d",last_kick,dut.duty[0]);
    last_kick=dut.duty[0];
   end
  end
  last_enable=(dut.channel_enable==4'b1111);
 end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task byte_tx(input[7:0] b);
  integer i;begin @(negedge clk);rx=0;clocks(10);
   for(i=0;i<8;i=i+1)begin rx=b[i];clocks(10);end
   rx=1;clocks(12);end
 endtask
 task healthy;
  begin
   force dut.wheels[0].directed_speed=17'sd20;
   force dut.wheels[1].directed_speed=17'sd20;
   force dut.wheels[2].directed_speed=17'sd20;
   force dut.wheels[3].directed_speed=17'sd20;
  end
 endtask
 integer n,saved_starts;
 initial begin
  force dut.imu_angle_valid=1'b1;force dut.tof_valid=4'b0001;
  force dut.tof_hard_stop=1'b0;force dut.tof_speed_scale_permille=10'd1000;
  healthy();clocks(5);rst=1;clocks(2200);
  if(pwm||in1||in2)$fatal(1,"boot movement");
  byte_tx("S");clocks(1200);
  byte_tx("F");clocks(1200);
  if(dut.channel_enable!=15 || dut.wheels[0].u_control.kick_active)
   $fatal(1,"forward start/PI handover failed");
  if(dut.duty[0]!=600)$fatal(1,"healthy PI handover not preserved");
  saved_starts=starts;byte_tx("F");clocks(200);
  if(starts!=saved_starts || dut.wheels[0].u_control.kick_active)
   $fatal(1,"heartbeat restarted kick");
  byte_tx("S");byte_tx("B");
  if(pwm||in1||in2)$fatal(1,"reversal neutral missing");
  clocks(400);if(pwm||in1||in2)$fatal(1,"reversal quiet too short");
  clocks(800);byte_tx("B");clocks(1200);
  if(dut.channel_enable!=15)$fatal(1,"reverse synchronized restart missing");
  byte_tx("S");clocks(3);if(pwm||in1||in2)$fatal(1,"S stop failed");
  clocks(1200);byte_tx("F");clocks(500);
  force dut.tof_hard_stop=1'b1;#1;
  if(pwm||in1||in2)$fatal(1,"hard stop waited for startup");
  clocks(10);force dut.tof_hard_stop=1'b0;byte_tx("S");clocks(1200);
  // Zero reference must reset the kick and never accumulate false stall.
  force dut.effective_target_counts=16'd0;byte_tx("F");clocks(1600);
  if(pwm || dut.channel_fault)$fatal(1,"zero-reference kick/fault");
  byte_tx("S");release dut.effective_target_counts;clocks(1200);
  // Same original 20 samples after the bounded 100ms kick: no relaxed loss limit.
  force dut.wheels[0].directed_speed=17'sd0;
  force dut.wheels[1].directed_speed=17'sd0;
  force dut.wheels[2].directed_speed=17'sd0;
  force dut.wheels[3].directed_speed=17'sd0;
  byte_tx("F");clocks(1600);
  if(dut.channel_fault)$fatal(1,"no-feedback protection fired early");
  byte_tx("F");
  clocks(1800);
  if(dut.channel_fault!=15 || pwm||in1||in2)$fatal(1,"stall protection/gating lost");
  if(dut.wheels[0].u_control.fault_reason_o!=1)$fatal(1,"fault evidence lost");
  $display("SIN12_SYNC_START_BOUNDED_KICK_REVERSAL_HARDSTOP_LOSS_PASS");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
