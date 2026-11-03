`timescale 1ns/1ps
module tb_sin12_r9_turn;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,av=0,hard=0,inv=0;reg[7:0] ab=0;reg[15:0]seq=0;
reg signed[15:0] yaw=0,angle=9000;
wire active,fault;wire[3:0]state;wire signed[15:0]target,error;wire[2:0]cmd;wire[15:0]speed;
imu_turn_guard #(.CLK_HZ(10000),.TIMEOUT_MS(20000),.NEUTRAL_MS(10),.PIPELINED_TARGET(1),.DAMPED_APPROACH(1)) dut(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.sequence_i(seq),.angle_cdeg_i(angle),
.speed_i(8'd12),.inverted_i(inv),.yaw_i(yaw),.sensors_ok_i(1'b1),.hard_stop_i(hard),.motor_fault_i(1'b0),
.other_active_i(1'b0),.cancel_i(1'b0),.ascii_valid_i(av),.error_i(1'b0),.ascii_i(ab),
.active_o(active),.fault_o(fault),.state_o(state),.sequence_o(),.target_yaw_o(target),.error_o(error),
.command_o(cmd),.target_speed_o(speed));
integer velocity=0,drive,yy,n,near_slow,coasting,changes,lastcmd,runs;
task step;begin
  drive=cmd==5?speed*16:cmd==6?-speed*16:0;
  if(inv)drive=-drive;
  // Test plant has momentum: removing drive does not instantly stop yaw.
  velocity=(velocity*3+drive)/4;
  yy=$signed(yaw)+velocity;if(yy>25736)yy=yy-51472;if(yy< -25736)yy=yy+51472;
  @(negedge clk);yaw=yy;av=1;ab="G";tick=1;
  @(negedge clk);tick=0;av=0;repeat(118)@(negedge clk);
end endtask
task start;begin
  av=1;ab="S";@(negedge clk);av=0;repeat(120)@(negedge clk);
  seq=seq+1;req=1;@(negedge clk);req=0;
  repeat(4)begin @(negedge clk);if(cmd)$fatal(1,"Pending conversion moved");end
end endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 for(runs=0;runs<4;runs=runs+1)begin
   yaw=runs==2?16'sd24500:runs==3?-16'sd24500:0;
   angle=runs[0]?-9000:9000;inv=runs==3;velocity=0;
   start;n=0;near_slow=0;coasting=0;changes=0;lastcmd=0;
   while(active && n<1800)begin
     if(cmd && speed<8)near_slow=near_slow+1;
     if(!cmd && velocity!=0)coasting=coasting+1;
     if(cmd && lastcmd && cmd!=lastcmd)changes=changes+1;
     if(cmd)lastcmd=cmd;
     step;n=n+1;
   end
   if(active || fault || state!=3 || $signed(error)>286 || $signed(error)<-286 || !near_slow || !coasting)
     $fatal(1,"Inertial turn failed run=%d state=%d err=%d slow=%d coast=%d",runs,state,error,near_slow,coasting);
   if(changes>3)$fatal(1,"Excessive direction hunting %d",changes);
   if(velocity>15 || velocity< -15)$fatal(1,"Reported DONE while rotating");
   $display("R9_INERTIAL_TURN_PASS run=%d samples=%d reversals=%d error=%d",runs,n,changes,error);
   repeat(30)step;if(active || cmd)$fatal(1,"Completed turn restarted");
 end
 yaw=0;angle=9000;inv=0;start;repeat(40)step;
 if(!cmd)$fatal(1,"Did not reach moving hard-stop test");hard=1;#1;
 if(cmd || speed)$fatal(1,"Physical hard-stop delayed");
 step;hard=0;repeat(30)step;
 if(active || cmd || state!=6)$fatal(1,"Hard stop restarted");
 $display("R9_TURN_PENDING_RATE_SETTLE_WRAP_INVERSION_HARDSTOP_PASS");$finish;
end
initial begin #100000000;$fatal(1,"Turn model timeout");end
endmodule
