`timescale 1ns/1ps
module tb_sin12_r6_trim_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,tick=0,en=0,valid=1;reg[2:0]cmd=0,owner=0;
 reg signed[15:0]yaw=0,s0=0,s1=0,s2=0,s3=0;
 wire signed[15:0]p0=cmd==5 ? -s0:s0,p1=cmd==6 ? -s1:s1;
 wire signed[15:0]p2=cmd==5 ? -s2:s2,p3=cmd==6 ? -s3:s3;
 wire[63:0]a,b;wire la,lb;wire[15:0]ra,rb,ea,eb;wire[7:0]ca,cb;
 chassis_trim old(.clk(clk),.rst_n(rst),.sample_tick_i(tick),.enable_i(en),.yaw_valid_i(valid),
 .command_i(cmd),.owner_i(owner),.yaw_i(yaw),.base_i(16'd12),
 .speed0_i(s0),.speed1_i(s1),.speed2_i(s2),.speed3_i(s3),.targets_o(a),
 .heading_locked_o(la),.reference_o(ra),.error_o(ea),.correction_o(ca));
 chassis_trim #(.PHYSICAL_SPEEDS(1)) revised(.clk(clk),.rst_n(rst),.sample_tick_i(tick),.enable_i(en),.yaw_valid_i(valid),
 .command_i(cmd),.owner_i(owner),.yaw_i(yaw),.base_i(16'd12),
 .speed0_i(p0),.speed1_i(p1),.speed2_i(p2),.speed3_i(p3),.targets_o(b),
 .heading_locked_o(lb),.reference_o(rb),.error_o(eb),.correction_o(cb));
 integer i;
 initial begin
 repeat(3)@(negedge clk);rst=1;
 for(i=0;i<1200;i=i+1)begin
  @(negedge clk);tick=i%3==0;en=i%31!=0;valid=i%43!=0;
  if(i%40==0)begin cmd=(i/40)%7;owner=(i/80)%4;end
  yaw=$urandom_range(0,4000)-2000;
  s0=$urandom_range(0,100)-50;s1=$urandom_range(0,100)-50;
  s2=$urandom_range(0,100)-50;s3=$urandom_range(0,100)-50;
  @(posedge clk);#1;
  if({a,la,ra,ea,ca} !== {b,lb,rb,eb,cb})$fatal(1,"trim differs at sample %d command%d",i,cmd);
 end
 $display("R6_PHYSICAL_ENCODER_TRIM_1200_CYCLE_EQUIVALENCE_PASS");$finish;
 end
endmodule
