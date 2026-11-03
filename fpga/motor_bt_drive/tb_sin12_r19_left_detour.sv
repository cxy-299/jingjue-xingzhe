`timescale 1ns/1ps
module tb_sin12_r19_left_detour;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,request=0,av=0,tf=0,ok=1,hard=0,mf=0,cancel=0,error=0;
reg [7:0] ab=0,sx=10,sy=2,gx=10,gy=6;
reg [15:0] seq=0,distance=1500,counts=500;
reg signed [15:0] yaw=0;
reg signed [15:0] mount_setback=0;
reg [31:0] p0=0,p1=0,p2=0,p3=0;
wire active,fault;wire [7:0] state,reason,replans,x,y;wire [2:0] cmd;wire [15:0] speed;
wire [7:0] goalx,goaly,obsx,obsy;
integer n,yy,moves,prevstate,legs,obstacles,coast=0;
reg renew=1,fresh=1,drive=1,inject=0,inject_second=0,blocked=0;
reg inertial=0;reg [2:0] previous_cmd=0;
reg [1:0] directions[0:15];
reg [399:0] mapbits=0;
autonomous_nav_guard #(.CELL_COUNTS(500),.NEUTRAL_TICKS(20),.SETTLE_TICKS(3),
 .MAX_TICKS(30000),.LEG_TICKS(3000),.CANCEL_PIPELINE(1),.LOCAL_MAP_ENABLE(1),
 .PROGRESS_CONTROL(1),.CONFIRMED_MAPPING(1),.ROUND_POSE_MM(1),.FIXED_LEFT_DETOUR(1),.DETOUR_FORWARD_CELLS(3),.LATCH_NEAR_EVENT(1)) dut(
 .clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(request),.sequence_i(seq),
 .sx_i(sx),.sy_i(sy),.gx_i(gx),.gy_i(gy),.flags_i(8'd5),.speed_i(8'd12),
 .counts_i(counts),.setback_i(mount_setback),.yaw_i(yaw),.sensors_ok_i(ok),.hard_stop_i(hard),
 .motor_fault_i(mf),.other_active_i(1'b0),.cancel_i(cancel),.ascii_valid_i(av),.ascii_i(ab),
 .error_i(error),.tof_sample_i(tf),.distance_i(distance),
 .position0_i(p0),.position1_i(p1),.position2_i(p2),.position3_i(p3),
 .active_o(active),.fault_o(fault),.state_o(state),.reason_o(reason),.replans_o(replans),
 .sequence_o(),.x_o(x),.y_o(y),.gx_o(goalx),.gy_o(goaly),.obstacle_x_o(obsx),.obstacle_y_o(obsy),
 .command_o(cmd),.speed_o(speed),.local_mode_o());
task step;begin
 @(negedge clk);tick=0;tf=0;av=0;
 if(state==7 && prevstate!=7)begin
   if(legs<16)directions[legs]=dut.direction;
   legs=legs+1;
 end
 prevstate=state;
 if(inertial && previous_cmd==1 && cmd==0 && state==8)coast=8;
 previous_cmd=cmd;
 if((drive && cmd==1)||coast>0)begin
   p0=p0+4;p1=p1-4;p2=p2+4;p3=p3-4;moves=moves+1;
   if(coast>0)coast=coast-1;
 end
 if(cmd==5)begin yy=$signed(yaw)+220;if(yy>25736)yy=yy-51472;yaw=yy;end
 if(cmd==6)begin yy=$signed(yaw)-220;if(yy< -25736)yy=yy+51472;yaw=yy;end
 if(cmd!=0 && cmd!=1 && cmd!=5 && cmd!=6)$fatal(1,"unexpected translation/backwards %0d",cmd);
 if(cmd==1 && speed!=4)$fatal(1,"R19 forward speed not capped %0d",speed);
 if(active && (goalx!=gx || goaly!=gy))$fatal(1,"original goal changed");
 // A short current near ray stops the moving state; stopped far rays do not
 // fabricate occupied cells. No force of internal registers is used.
 distance=1500;
 if(inject && !blocked && state==7 && dut.direction==0 && dut.advance>60)begin
   distance=300;blocked=1;obstacles=obstacles+1;
 end
 if(inject_second && obstacles==1 && state==7 && dut.detour_leg==2 && dut.advance>60)begin
   distance=300;obstacles=obstacles+1;
 end
 #1;if(distance<=400 && cmd!=0)$fatal(1,"new obstacle failed immediate stop");
 repeat(18)@(negedge clk);tick=1;tf=fresh;av=renew;ab="N";
 @(negedge clk);tick=0;tf=0;av=0;
end endtask
task boot;begin
 rst=0;repeat(5)@(negedge clk);rst=1;
 p0=0;p1=0;p2=0;p3=0;yaw=0;distance=1500;renew=1;fresh=1;drive=1;coast=0;
 ok=1;hard=0;mf=0;cancel=0;error=0;seq=seq+1;legs=0;moves=0;prevstate=0;
 blocked=0;obstacles=0;inject=0;inject_second=0;counts=500;
 inertial=0;previous_cmd=0;
 mount_setback=0;
 repeat(25)step;
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;
 repeat(25)step;
end endtask
task check_projection(input integer targetx,targety,offset_mm,expectedx,expectedy);begin
 boot;sx=10;sy=10;gx=targetx;gy=targety;mount_setback=offset_mm;start_job;
 n=0;while(active && state!=6 && n<5000)begin step;n=n+1;end
 if(state!=6)$fatal(1,"projection probe unavailable");
 distance=150;n=0;
 while(active && obsx==255 && n<5000)begin
   @(negedge clk);tick=1;tf=1;av=1;ab="N";
   @(negedge clk);tick=0;tf=0;av=0;repeat(18)@(negedge clk);n=n+1;
 end
 if(obsx!=expectedx || obsy!=expectedy)$fatal(1,"cardinal/setback projection wrong %d,%d expected%d,%d",obsx,obsy,expectedx,expectedy);
end endtask
task check_negative_detour(input integer targetx,targety,heading);begin
 boot;sx=10;sy=10;gx=targetx;gy=targety;start_job;
 n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 step;
 @(negedge clk);distance=300;#1;if(cmd)$fatal(1,"negative-axis near did not stop");
 repeat(3)@(negedge clk);distance=1500;
 finish_job;
 if(replans!=1 || directions[1]!=((heading+1)%4) || directions[2]!=heading ||
    directions[3]!=heading || directions[4]!=heading || directions[5]!=((heading+3)%4))
   $fatal(1,"negative-axis detour order wrong heading=%d",heading);
end endtask
task start_job;begin @(negedge clk);request=1;@(negedge clk);request=0;end endtask
task finish_job;begin
 n=0;while(active && n<25000)begin step;n=n+1;end
 if(active || state!=11 || fault || x!=gx || y!=gy)
   $fatal(1,"goal not completed s=%0d e=%0d xy=%0d,%0d target=%0d,%0d detour=%0d",state,reason,x,y,gx,gy,dut.detour_leg);
end endtask
initial begin
 boot;start_job;finish_job;
 if(legs!=4 || p0<1800 || p0>2100)$fatal(1,"500-count grid scale/leg count %0d %0d",legs,p0);
 $display("R19_500_COUNTS_FOUR_CELLS_ORIGINAL_ENDPOINT_PASS");
 boot;inertial=1;start_job;finish_job;
 if(p0<1950 || p0>2050)$fatal(1,"coast model endpoint wrong %0d",p0);
 $display("R19_BRAKE_COAST_STILL_GATE_ENDPOINT_NO_TOLERANCE_RELAX_PASS");
 boot;counts=333;start_job;
 if(active || reason!=6)$fatal(1,"legacy333 accepted");
 $display("R19_OLD333_REJECTED_PASS");
 boot;inject=1;start_job;finish_job;
 if(obstacles!=1 || replans!=1 || legs<5)$fatal(1,"missing detour");
 if(directions[0]!=0 || directions[1]!=1 || directions[2]!=0 || directions[3]!=0 || directions[4]!=0 || directions[5]!=3)
   $fatal(1,"detour sequence not forward-left-forward-right %0d %0d %0d %0d",directions[0],directions[1],directions[2],directions[3]);
 $display("R19_LEFT_ONE_FORWARD_THREE_RIGHT_ONE_RESTORE_AND_GOAL_PASS");
 boot;inject=1;inject_second=1;start_job;finish_job;
 if(obstacles!=2 || replans!=2)$fatal(1,"second obstacle not handled %0d %0d",obstacles,replans);
 $display("R19_SECOND_NEW_OBSTACLE_STOP_NEW_LEFT_DETOUR_KEEP_GOAL_PASS");
 boot;sx=0;gx=0;inject=1;start_job;
 n=0;while(active && n<6000)begin step;n=n+1;end
 if(active || reason!=14 || cmd)$fatal(1,"left boundary not stopped s%0d e%0d",state,reason);
 $display("R19_LEFT_BOUNDARY_SAFE_STOP_PASS");sx=10;gx=10;
 boot;start_job;n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 @(negedge clk);cancel=1;#1;if(cmd)$fatal(1,"cancel not immediate");
 @(negedge clk);cancel=0;#1;if(cmd)$fatal(1,"cancel rebound");repeat(20)step;
 if(active)$fatal(1,"cancel did not terminate");
 $display("R19_CANCEL_NO_REBOUND_PASS");
 boot;start_job;n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 @(negedge clk);hard=1;#1;if(cmd)$fatal(1,"hardstop not immediate");step;hard=0;repeat(20)step;
 if(active || reason!=4)$fatal(1,"hardstop restart");
 $display("R19_HARD_STOP_NO_RESTART_PASS");
 boot;start_job;n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 renew=0;repeat(40)step;
 if(active || reason!=1 || cmd)$fatal(1,"lease expiry not stopped");
 $display("R19_LEASE_STOP_PASS");
 boot;start_job;n=0;while(active && state!=6 && n<5000)begin step;n=n+1;end
 fresh=0;repeat(110)step;
 if(active || reason!=8 || cmd)$fatal(1,"stale range probe moved");
 $display("R19_NO_FRESH_RANGE_SAFE_STOP_PASS");
 boot;sx=10;sy=8;gx=14;gy=8;inject=1;start_job;
 // Inject after the first east-facing leg starts, using the public ToF input.
 n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 step; // Record the first east MOVE leg before injecting its near ray.
 distance=300;#1;if(cmd)$fatal(1,"east near not stopped");
 @(negedge clk);tick=1;@(negedge clk);tick=0;distance=1500;inject=0;
 finish_job;
 if(replans!=1 || directions[1]!=0 || directions[2]!=3 || directions[3]!=3 || directions[4]!=3 || directions[5]!=2)
   $fatal(1,"east relative left/forward/right sequence wrong %0d %0d %0d",directions[1],directions[2],directions[3]);
 $display("R19_EAST_RELATIVE_LEFT_FORWARD_RIGHT_KEEP_ENDPOINT_PASS");
 // A near event shorter than one 10ms tick must remain stopped even after
 // the range becomes far again. No internal force; use only public inputs.
 boot;sx=10;sy=2;gx=10;gy=8;start_job;
 n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 @(negedge clk);distance=300;#1;if(cmd)$fatal(1,"subtick near did not stop");
 repeat(3)@(negedge clk);distance=1500;
 #1;if(state!=8 || cmd)$fatal(1,"subtick event rebounded state=%0d command=%0d",state,cmd);
 finish_job;
 if(replans!=1)$fatal(1,"subtick event not handled");
 $display("R19_SUBTICK_NEAR_LATCH_NO_REBOUND_KEEP_GOAL_PASS");
 // Stopped window projects 125mm from a (17,2) cell centre: 250+100+125
 // is y475mm -> cell4, independent of the selected destination.
 boot;sx=17;sy=2;gx=17;gy=11;start_job;
 n=0;while(active && state!=6 && n<5000)begin step;n=n+1;end
 distance=125;
 n=0;while(active && obsx==255 && n<5000)begin
   @(negedge clk);tick=1;tf=1;av=1;ab="N";
   @(negedge clk);tick=0;tf=0;av=0;repeat(18)@(negedge clk);n=n+1;
 end
 if(obsx!=17 || obsy!=4)$fatal(1,"stationary projection wrong %d,%d",obsx,obsy);
 $display("R19_STOPPED_POSE_TOF_PROJECTS_EXACT_CELL_17_4_PASS");
 // A subsequent outward ray from the north edge cannot retain that old cell.
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;
 sx=17;sy=19;gx=18;gy=19;distance=1500;seq=seq+1;
 repeat(25)step;start_job;
 n=0;while(active && state!=6 && n<5000)begin step;n=n+1;end
 distance=400;
 n=0;while(active && n<5000)begin
   @(negedge clk);tick=1;tf=1;av=1;ab="N";
   @(negedge clk);tick=0;tf=0;av=0;repeat(18)@(negedge clk);n=n+1;
 end
 if(obsx!=255 || obsy!=255)$fatal(1,"outside ray retained wrong obstacle cell %d,%d",obsx,obsy);
 $display("R19_OUT_OF_FIELD_RAY_NO_STALE_OBSTACLE_CELL_PASS");
 check_projection(14,10,0,13,10);
 $display("R19_EAST_STOPPED_PROJECTION_PASS");
 check_projection(6,10,0,8,10);
 $display("R19_WEST_STOPPED_PROJECTION_PASS");
 check_projection(10,6,0,10,8);
 $display("R19_SOUTH_STOPPED_PROJECTION_PASS");
 check_projection(14,10,50,12,10);
 $display("R19_POSITIVE_SETBACK_GRID_BOUNDARY_PASS");
 check_projection(14,10,-30,13,10);
 $display("R19_NEGATIVE_SETBACK_GRID_BOUNDARY_PASS");
 check_negative_detour(6,10,1);
 $display("R19_WEST_LEFT_FORWARD_THREE_RIGHT_KEEP_GOAL_PASS");
 check_negative_detour(10,6,2);
 $display("R19_SOUTH_LEFT_FORWARD_THREE_RIGHT_KEEP_GOAL_PASS");
 sx=10;sy=2;gx=10;gy=6;
 $display("R19_FIXED_LEFT_NAV_ALL_PASS");$finish;
end
initial begin #100000000;$fatal(1,"bench timeout");end
endmodule
