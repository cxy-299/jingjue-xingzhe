`timescale 1ns/1ps
module tb_sin12_r20_adaptive;
reg clk=0;always #10 clk=~clk;
reg rst=0,tick=0,request=0,av=0,tf=0,ok=1,hard=0,mf=0,cancel=0,error=0;
reg [7:0] ab=0,sx=10,sy=2,gx=10,gy=6;
reg [15:0] seq=0,distance=1500,counts=500;
reg signed [15:0] yaw=0;
reg signed [15:0] mount_setback=0;
reg [31:0] p0=0,p1=0,p2=0,p3=0;
wire active,fault;wire [7:0] state,reason,replans,x,y;wire [2:0] cmd;wire [15:0] speed;
wire [7:0] goalx,goaly,obsx,obsy;
integer n,yy,moves,prevstate,legs,obstacles,coast=0;
integer minx,miny,maxx,maxy;
reg renew=1,fresh=1,drive=1,inject=0,inject_second=0,blocked=0;
reg held_near=0;reg[15:0] held_distance=200;
reg inertial=0;reg [2:0] previous_cmd=0;
reg [1:0] directions[0:15];
reg [399:0] mapbits=0;
autonomous_nav_guard #(.CELL_COUNTS(500),.EARLY_STOP_MM(200),.NEUTRAL_TICKS(20),.SETTLE_TICKS(3),
 .MAX_TICKS(30000),.LEG_TICKS(3000),.CANCEL_PIPELINE(1),.LOCAL_MAP_ENABLE(1),
 .PROGRESS_CONTROL(1),.CONFIRMED_MAPPING(1),.ROUND_POSE_MM(1),.FIXED_LEFT_DETOUR(1),.DETOUR_FORWARD_CELLS(3),.LATCH_NEAR_EVENT(1),.ADAPTIVE_DETOUR(1),.CONSERVATIVE_CELLS(1)) dut(
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
 if(active)begin if(x<minx)minx=x;if(y<miny)miny=y;if(x>maxx)maxx=x;if(y>maxy)maxy=y;end
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
 distance=held_near?held_distance:1500;
 if(inject && !blocked && state==7 && dut.direction==0 && dut.advance>60)begin
   distance=300;blocked=1;obstacles=obstacles+1;
 end
 if(inject_second && obstacles==1 && state==7 && dut.detour_leg==2 && dut.advance>60)begin
   distance=300;obstacles=obstacles+1;
 end
 #1;if(distance<=200 && cmd==1)$fatal(1,"new obstacle failed immediate stop");
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
task check_cells;integer ix,iy,dxmm,dymm,oxmm,oymm,k,expected;begin
 while(active && state==9)step;
 oxmm=$signed(dut.obstacle_x);oymm=$signed(dut.obstacle_y);
 for(iy=0;iy<20;iy=iy+1)for(ix=0;ix<20;ix=ix+1)begin
   dxmm=oxmm<ix*100?ix*100-oxmm:oxmm>(ix+1)*100?oxmm-(ix+1)*100:0;
   dymm=oymm<iy*100?iy*100-oymm:oymm>(iy+1)*100?oymm-(iy+1)*100:0;
   expected=dxmm*dxmm+dymm*dymm<=210*210;
   if(dut.occupied[iy*20+ix]!==expected[0])$fatal(1,"cell intersection mismatch cell=%0d,%0d point=%0d,%0d got%b exp%0d",ix,iy,oxmm,oymm,dut.occupied[iy*20+ix],expected);
 end
end endtask
task check_route(input integer startx,starty,targetx,targety,range_mm,expectx,expecty);begin
 boot;sx=startx;sy=starty;gx=targetx;gy=targety;mount_setback=-4;held_distance=range_mm;held_near=1;
 minx=startx;maxx=startx;miny=starty;maxy=starty;start_job;
 n=0;while(active && obsx==255 && n<5000)begin step;n=n+1;end
 if(obsx!=expectx || obsy!=expecty)$fatal(1,"wrong point got%0d,%0d exp%0d,%0d",obsx,obsy,expectx,expecty);
 held_near=0;distance=1500;check_cells;finish_job;
 if(replans!=1)$fatal(1,"wrong replans%0d",replans);
 if(startx==targetx && minx>startx-3 && maxx<startx+3)$fatal(1,"no wide sidestep");
 if(starty==targety && miny>starty-3 && maxy<starty+3)$fatal(1,"no wide sidestep");
 $display("R20_ADAPTIVE_FRACTIONAL_OBSTACLE_GOAL_PASS range=%0d start=%0d,%0d goal=%0d,%0d obs=%0d,%0d bounds=%0d,%0d..%0d,%0d",range_mm,startx,starty,targetx,targety,obsx,obsy,minx,miny,maxx,maxy);
end endtask
initial begin
 check_route(10,5,10,12,200,10,8);
 check_route(10,12,10,5,197,10,9);
 check_route(12,10,5,10,163,9,10);
 check_route(5,10,12,10,163,8,10);

 check_route(10,5,10,12,196,10,8);
 check_route(5,10,12,10,149,8,10);
 held_near=0;boot;sx=5;sy=10;gx=12;gy=10;mount_setback=50;held_distance=125;held_near=1;start_job;
 n=0;while(active && n<20000)begin step;n=n+1;end
 if(active || reason!=14 || cmd)$fatal(1,"actual pose inside safety radius escaped");
 $display("R20_ACTUAL_POSE_INSIDE_SAFETY_RADIUS_NO_ESCAPE_PASS");
 held_near=0;boot;sx=17;sy=2;gx=17;gy=11;start_job;
 n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 @(negedge clk);distance=300;#1;if(cmd!=1)$fatal(1,"300mm triggered200mm");
 @(negedge clk);distance=200;#1;if(cmd)$fatal(1,"200mm stop delayed");
 $display("R20_200MM_TRIGGER_NOT_300MM_PASS");
 held_near=0;boot;sx=17;sy=2;gx=17;gy=11;start_job;
 n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 @(negedge clk);hard=1;#1;if(cmd)$fatal(1,"hard stop delayed");step;hard=0;repeat(20)step;
 if(active || reason!=4)$fatal(1,"hard stop resumed");
 $display("R20_HARD_STOP_NO_RESTART_PASS");
 held_near=0;boot;sx=17;sy=2;gx=17;gy=11;start_job;
 n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 @(negedge clk);cancel=1;#1;if(cmd)$fatal(1,"cancel delayed");@(negedge clk);cancel=0;repeat(20)step;
 if(active || cmd)$fatal(1,"cancel resumed");
 $display("R20_CANCEL_NO_RESTART_PASS");
 held_near=0;boot;sx=17;sy=2;gx=17;gy=11;start_job;
 n=0;while(active && state!=7 && n<5000)begin step;n=n+1;end
 @(negedge clk);ok=0;#1;if(cmd)$fatal(1,"sensor loss delayed");@(negedge clk);ok=1;repeat(20)step;
 if(active || reason!=2 || cmd)$fatal(1,"sensor loss resumed");
 $display("R20_SENSOR_LOSS_NO_RESTART_PASS");
 $display("R20_ADAPTIVE_ALL_PASS");$finish;
end
initial begin #100000000;$fatal(1,"adaptive timeout");end
endmodule
