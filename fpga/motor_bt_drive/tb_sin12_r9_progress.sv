`timescale 1ns/1ps
module tb_sin12_r9_progress;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,request=0,av=0,tf=0;reg[7:0] ab=0,sy=2,gy=9;
reg[15:0] seq=1;reg signed[15:0] yaw=0;
reg[31:0] p0=0,p1=0,p2=0,p3=0;wire active,fault;wire[7:0]state,reason,x,y,gxout,gyout;wire[2:0]cmd;wire[15:0]speed;
autonomous_nav_guard #(.CELL_COUNTS(1000),.LOCAL_MAP_ENABLE(5),.CANCEL_PIPELINE(1),.PROGRESS_CONTROL(1)) dut(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(request),.sequence_i(seq),
.sx_i(8'd17),.sy_i(sy),.gx_i(8'd17),.gy_i(gy),.flags_i(8'd1),.speed_i(8'd12),
.counts_i(16'd1000),.setback_i(16'sd0),.yaw_i(yaw),.sensors_ok_i(1'b1),.hard_stop_i(1'b0),
.motor_fault_i(1'b0),.other_active_i(1'b0),.cancel_i(1'b0),.ascii_valid_i(av),.ascii_i(ab),.error_i(1'b0),
.tof_sample_i(tf),.distance_i(16'd2000),.position0_i(p0),.position1_i(p1),.position2_i(p2),.position3_i(p3),
.active_o(active),.fault_o(fault),.state_o(state),.reason_o(reason),.replans_o(),.sequence_o(),
.x_o(x),.y_o(y),.gx_o(gxout),.gy_o(gyout),.obstacle_x_o(),.obstacle_y_o(),.command_o(cmd),.speed_o(speed),.local_mode_o());
task step;begin
 @(negedge clk);tick=0;tf=0;av=0;repeat(20)@(negedge clk);tick=1;tf=1;av=1;ab="N";
 @(negedge clk);tick=0;tf=0;av=0;
end endtask
task arm;begin
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;
 repeat(25)step;@(negedge clk);request=1;@(negedge clk);request=0;
end endtask
integer n,slow_samples,brakes,yy;
initial begin
 repeat(5)@(negedge clk);rst=1;arm;
 n=0;while(active && state!=7 && n<2000)begin step;n=n+1;end
 if(state!=7)$fatal(1,"No initial MOVE");
 // Exact recorded counterexample, through external encoder inputs only.
 p0=1100;p1=-32'sd1100;p2=1100;p3=-32'sd1100;
 n=0;while(active && !(state==7 && dut.ty==4500) && n<1000)begin
   step;n=n+1;
   if(state==4 && dut.direction==2)$fatal(1,"Turned 180 to chase passed intermediate waypoint");
   if(state==11)$fatal(1,"Intermediate waypoint announced as destination");
   if(gxout!=17 || gyout!=9)$fatal(1,"Submitted goal mutated");
 end
 if(!active || state!=7 || dut.ty!=4500)$fatal(1,"Did not advance toward submitted goal state=%d reason=%d",state,reason);
 $display("R9_PASSED_INTERMEDIATE_NO_REVERSE_GOAL_IMMUTABLE_PASS");
 slow_samples=0;brakes=0;n=0;
 while(active && n<10000)begin
   if(cmd==1)begin
     p0=p0+20;p1=p1-20;p2=p2+20;p3=p3-20;
     if(speed==8)slow_samples=slow_samples+1;
   end
   if(state==8 && dut.advance<dut.travel)brakes=brakes+1;
   if(cmd==5 || cmd==6)$fatal(1,"Clear straight route unexpectedly commanded rotation");
   step;n=n+1;
   if(state==11 && (x!=17 || y!=9))$fatal(1,"DONE at non-goal cell");
 end
 if(state!=11 || fault || x!=17 || y!=9 || !slow_samples || !brakes)
   $fatal(1,"Goal arrival/deceleration failed state=%d reason=%d slow=%d brake=%d",state,reason,slow_samples,brakes);
 repeat(50)step;if(active || cmd)$fatal(1,"DONE restarted");
 $display("R9_FINAL_GOAL_ONLY_TAPER_EARLY_BRAKE_STOP_PASS");
 // Passing the FINAL centre by 35mm is explicitly NOT successful arrival.
 rst=0;repeat(3)@(negedge clk);rst=1;seq=2;gy=3;p0=0;p1=0;p2=0;p3=0;arm;
 n=0;while(active && state!=7 && n<2000)begin step;n=n+1;end
 p0=1350;p1=-32'sd1350;p2=1350;p3=-32'sd1350;
 n=0;while(active && n<1000)begin step;n=n+1;end
 if(state!=12 || reason!=13 || !fault || cmd)$fatal(1,"Large final overshoot accepted/reversed state=%d reason=%d",state,reason);
 $display("R9_FINAL_OVERSHOOT_NOT_ARRIVAL_NO_HUNT_PASS");$finish;
end
initial begin #100000000;$fatal(1,"Progress test timeout");end
endmodule
