`timescale 1ns/1ps
// Black-box mission + real trim outputs drive a simplified disturbed chassis
// and camera-centre model. This checks feedback polarity, not real traction.
module tb_sin12_r10_alignment_plant;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,pkt=0,av=0;reg[7:0]ab=0;reg[15:0]seq=0;
reg signed[15:0]center=-4500,yaw=0;reg[15:0]distance=900;
wire active;wire[2:0]cmd;wire[15:0]speed;wire[3:0]state;wire[63:0]targets;wire headinglocked;
reg[2:0]phase=0;wire still=cmd==0;
vision_mission_guard #(.CLK_HZ(1000),.CONTROLLED_ALIGN(1),.ARRIVAL_TICKS(3)) mission(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.request_id_i(32'd1),.request_class_i(16'd39),.request_distance_i(16'd300),
.request_red_i(1'b0),.request_inverted_i(1'b0),.packet_i(pkt),.packet_sequence_i(seq),.packet_mission_i(32'd1),.packet_lock_i(32'd42),
.packet_class_i(16'd39),.packet_red_i(1'b0),.selected_i(1'b1),.visible_i(1'b1),.confirmed_i(1'b1),.center_i(center),.yaw_i(yaw),
.distance_i(distance),.distance_sample_i(1'b0),.sensors_ok_i(1'b1),.hard_stop_i(1'b0),.motor_fault_i(1'b0),.other_active_i(1'b0),.cancel_i(1'b0),
.wheels_still_i(still),.ascii_valid_i(av),.error_i(1'b0),.ascii_i(ab),.active_o(active),.id_o(),.lock_o(),.class_o(),.state_o(state),
.leg_o(),.command_o(cmd),.speed_o(speed));
chassis_trim #(.PHYSICAL_SPEEDS(1),.LATERAL_HEADING(1)) trim(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.enable_i(cmd!=0),.yaw_valid_i(1'b1),.command_i(cmd),.owner_i(active?3'd2:3'd0),
.yaw_i(yaw),.base_i(speed),.speed0_i(16'sd0),.speed1_i(16'sd0),.speed2_i(16'sd0),.speed3_i(16'sd0),.targets_o(targets),
.heading_locked_o(headinglocked),.reference_o(),.error_o(),.correction_o());
integer i,a,b,c,d,torque,lateral,v=0,yy,maxyaw=0,heading_samples=0;
task step;begin
 @(negedge clk);pkt=0;av=0;tick=0;
 if(i%10==0)begin
  a=targets[15:0];b=targets[31:16];c=targets[47:32];d=targets[63:48];
  if(cmd==3)begin b=-b;c=-c;end else if(cmd==4)begin a=-a;d=-d;end
  else begin a=0;b=0;c=0;d=0;end
  torque=-a+b-c+d;lateral=-a+b+c-d;
  // Add a fixed yaw disturbance during every sideways move, then coast.
  v=(v*3+((cmd==3||cmd==4)?40:0)+torque*12)/4;
  yy=$signed(yaw)+v;yaw=yy;
  if(yy>maxyaw)maxyaw=yy;
  if(cmd==3||cmd==4)begin center=$signed(center)-lateral*3;if(headinglocked)heading_samples=heading_samples+1;end
  if(cmd==1 && distance>310)distance=distance-4;
  tick=1;
 end
 if(i%20==0)begin pkt=1;seq=seq+1;end
 if(i%50==0)begin av=1;ab="M";end
 @(posedge clk);#1;pkt=0;tick=0;av=0;
end endtask
initial begin
 repeat(4)@(negedge clk);rst=1;av=1;ab="S";@(negedge clk);av=0;
 for(i=0;i<200;i=i+1)step;
 @(negedge clk);req=1;@(negedge clk);req=0;
 for(i=0;i<20000 && (i<10||active);i=i+1)step;
 if(active || state!=6 || maxyaw>=1144 || !heading_samples || center< -1200 || center>1200)
   $fatal(1,"Disturbed lateral plant failed state=%d maxyaw=%d centre=%d locked=%d",state,maxyaw,center,heading_samples);
 $display("R10_DISTURBED_LATERAL_LOCK_ALIGN_APPROACH_ARRIVAL_PASS maxyawQ13=%d samples=%d",maxyaw,i);$finish;
end
initial begin #1000000;$fatal(1,"Chassis model timeout");end
endmodule
