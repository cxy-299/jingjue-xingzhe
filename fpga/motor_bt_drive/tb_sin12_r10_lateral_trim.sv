`timescale 1ns/1ps
module tb_sin12_r10_lateral_trim;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,en=0,valid=1;reg[2:0]cmd=0,owner=2;
reg signed[15:0]yaw=0;reg[15:0]base=6;
wire[63:0]targets;wire locked;wire signed[15:0]refyaw,err;wire signed[7:0]corr;
chassis_trim #(.PHYSICAL_SPEEDS(1),.LATERAL_HEADING(1)) dut(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.enable_i(en),.yaw_valid_i(valid),.command_i(cmd),.owner_i(owner),
.yaw_i(yaw),.base_i(base),.speed0_i(16'sd0),.speed1_i(16'sd0),.speed2_i(16'sd0),.speed3_i(16'sd0),
.targets_o(targets),.heading_locked_o(locked),.reference_o(refyaw),.error_o(err),.correction_o(corr));
task clocks(input integer n);repeat(n)@(negedge clk);endtask
task sample;begin tick=1;clocks(1);tick=0;clocks(4);
 if($isunknown({targets,locked,refyaw,err,corr}))$fatal(1,"Unknown lateral output cannot count as a pass");
end endtask
integer direction,sign_yaw,t0,t1,t2,t3,yawtorque,netforward,netlateral,k;
task vector_check;
begin
 t0=targets[15:0];t1=targets[31:16];t2=targets[47:32];t3=targets[63:48];
 if(cmd==3)begin t1=-t1;t2=-t2;end else begin t0=-t0;t3=-t3;end
 yawtorque=-t0+t1-t2+t3;netforward=t0+t1+t2+t3;netlateral=-t0+t1+t2-t3;
 if(netforward!=0)$fatal(1,"Lateral correction added forward motion");
 if((cmd==3 && netlateral>=0)||(cmd==4 && netlateral<=0))$fatal(1,"Lateral direction reversed");
 if((err<0 && yawtorque>=0)||(err>0 && yawtorque<=0))$fatal(1,"Correction yaw positive feedback err=%d torque=%d",err,yawtorque);
 if(t0==0||t1==0||t2==0||t3==0)$fatal(1,"Trim stopped a running wheel");
end endtask
initial begin
 clocks(3);rst=1;
 for(direction=3;direction<=4;direction=direction+1)begin
  for(sign_yaw=-1;sign_yaw<=1;sign_yaw=sign_yaw+2)begin
   en=0;cmd=0;owner=0;clocks(3);owner=2;cmd=direction;yaw=10000;en=1;clocks(6);
   if(locked!==1'b1||refyaw!==16'sd10000)$fatal(1,"Lateral initial heading not locked");
   yaw=10000+sign_yaw*1000;sample;vector_check;
   if(corr>2||corr< -2)$fatal(1,"Low-speed trim asymmetrically clips");
   // A mission STOP/coast and side change retain the SAME starting heading.
   cmd=0;en=0;clocks(10);sample;
   if(!locked||refyaw!=10000||targets)$fatal(1,"Pause lost reference or drove outputs");
   cmd=direction==3?4:3;en=1;clocks(4);sample;vector_check;
   if(refyaw!=10000)$fatal(1,"Opposite correction re-zeroed accumulated yaw");
   owner=0;clocks(4);if(refyaw==10000)$fatal(1,"New owner inherited mission reference");
  end
 end
 en=0;cmd=0;owner=0;clocks(3);cmd=3;owner=2;en=1;yaw=25500;clocks(6);yaw=-25500;sample;
 if(err>=0||err< -1000)$fatal(1,"Lateral +/-pi wrap failed");vector_check;
 valid=0;clocks(3);if(locked||corr)$fatal(1,"Invalid yaw retained trim");
 valid=1;clocks(5);base=0;clocks(3);if(targets)$fatal(1,"Zero reference raised wheel target");
 $display("R10_LATERAL_LEFT_RIGHT_SIGN_WRAP_PAUSE_OWNER_LOW_SPEED_PASS");$finish;
end
endmodule
