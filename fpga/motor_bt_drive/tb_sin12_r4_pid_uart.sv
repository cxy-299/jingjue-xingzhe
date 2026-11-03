`timescale 1ns/1ps
module tb_sin12_r4_pid_uart;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,rx=1;wire tx;wire[3:0] pwm;
 acg720_motor_bt_drive #(.CLK_HZ(10000),.PWM_HZ(100),.BT_BAUD(1000),.DIAG_BAUD(1000),
  .STARTUP_MS(1),.AUTO_NAV_ENABLE(1),.ROTATE_ENABLE(1),.VISION_ENABLE(1),.MISSION_ENABLE(1),
  .SENSOR_ENABLE(1),.TOF_HARD_STOP_MM(100),.DIAG_ENABLE(0)) dut(
  .clk_50m_i(clk),.key_s0_n_i(rst),.bt_uart_rx_i(rx),.pi_uart_rx_i(1'b1),
  .imu_uart_rx_i(1'b1),.tof0_uart_rx_i(1'b1),.encoder_a_i(4'b0),.encoder_b_i(4'b0),
  .motor_pwm_o(pwm),.motor_in1_o(),.motor_in2_o(),.led_o(),.diag_uart_tx_o(),.bt_uart_tx_o(tx));
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task byte_tx(input[7:0] b);
  integer i;begin @(negedge clk);rx=0;clocks(10);for(i=0;i<8;i=i+1)begin rx=b[i];clocks(10);end rx=1;clocks(12);end
 endtask
 function[15:0] crc_next(input[15:0] c,input[7:0] b);
  reg[15:0] v;integer k;begin v=c^{b,8'h0};for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc_next=v;end
 endfunction
 task config_tx(input[15:0] seq,p,i,d,input bit corrupt);
  reg[95:0] data;reg[15:0] crc;integer j;reg[7:0] b;
  begin
   data={d,i,p,16'd6,seq,8'h27,8'h03};crc=16'hffff;
   byte_tx(8'haa);byte_tx(8'h55);
   for(j=0;j<12;j=j+1)begin b=data[j*8+:8];crc=crc_next(crc,b);byte_tx(b);end
   byte_tx(crc[7:0] ^ (corrupt?1:0));byte_tx(crc[15:8]);clocks(5);
  end
 endtask
 wire[7:0] out_byte;wire out_valid;
 uart_rx #(.CLK_HZ(10000),.BAUD(1000)) monitor(.clk(clk),.rst_n(rst),.uart_rx_i(tx),.data_o(out_byte),.data_valid_o(out_valid),.framing_error_o());
 reg patterned=0;
 reg[223:0] record=0;reg[55:0] krecord=0;integer count=0,cs=0,ks=0;reg[7:0] kind=0;
 function[3:0] unhex(input[7:0] b);begin unhex=b<="9"?b-"0":b-"A"+10;end endfunction
 always @(negedge clk)if(out_valid)begin
  if(out_byte==10)begin
   if(kind=="C" && patterned)begin
    if(count!=58)$fatal(1,"C length %d",count);
    if($signed(record[127:112])!=$signed(record[111:96])-1 ||
       $signed(record[95:80])!=$signed(record[111:96])+1 ||
       $signed(record[79:64])!=$signed(record[111:96])+2)$fatal(1,"mixed four-wheel sample %h",record);
    cs=cs+1;
   end
   if(kind=="K")begin if(count!=16 || krecord[55:48]!=4)$fatal(1,"K bad record");ks=ks+1;end
   kind=0;count=0;
  end else begin
   if(count==0)begin kind=out_byte;record=0;krecord=0;end
   else if(out_byte!=13)begin
    if(kind=="C")record={record[219:0],unhex(out_byte)};
    if(kind=="K")krecord={krecord[51:0],unhex(out_byte)};
   end
   count=count+1;
  end
 end
 reg signed[16:0] s0=0,s1=0,s2=0,s3=0;integer epochs=0;
 always @(negedge clk)if(patterned && dut.sample_tick)begin
  epochs=epochs+1;s0=epochs%8;s1=s0+1;s2=s0+2;s3=s0+3;
 end
 initial begin
  force dut.imu_angle_valid=1;force dut.imu_yaw_raw=32'd0;force dut.tof_valid=1;
  force dut.tof_hard_stop=0;force dut.tof_speed_scale_permille=1000;
  force dut.wheels[0].directed_speed=s0;force dut.wheels[1].directed_speed=s1;
  force dut.wheels[2].directed_speed=s2;force dut.wheels[3].directed_speed=s3;
  clocks(5);rst=1;clocks(3000);byte_tx("S");clocks(3000);
  config_tx(16'h1234,8,0,2,0);
  if(dut.pid_p!=8 || dut.pid_i!=0 || dut.pid_d!=2 || dut.pid_status!=1 || pwm)$fatal(1,"stopped PID apply");
  config_tx(16'h1235,4,1,0,1);
  if(dut.pid_sequence!=16'h1234 || dut.pid_p!=8)$fatal(1,"bad CRC changed gains");
  config_tx(16'h1236,16'h0046,1,0,0); // ASCII F inside a valid binary payload
  if(dut.pid_status!=3 || dut.command!=0 || pwm)$fatal(1,"range/ASCII quarantine");
  byte_tx("S");clocks(1500);byte_tx("F");clocks(50);
  config_tx(16'h1237,4,1,0,0);
  if(dut.pid_status!=2 || dut.pid_p!=8)$fatal(1,"moving apply not rejected");
  byte_tx("S");clocks(3000);config_tx(16'h1238,4,1,0,0);
  if(dut.pid_status!=1 || dut.pid_p!=4 || dut.pid_d!=0)$fatal(1,"restore defaults apply");
  // Only inspect C frames after pattern generator starts, clear any prior frame.
  wait(dut.u_bt_diag.frame_kind==0 && dut.u_bt_diag.state==0);
  patterned=1;
  wait(cs>=2 && ks>=2);clocks(100);
  if(pwm || dut.channel_fault)$fatal(1,"telemetry caused motion/fault");
  $display("R4_REAL_UART_PID_CRC_RANGE_BUSY_READBACK_ATOMIC_SNAPSHOT_PASS");$finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
