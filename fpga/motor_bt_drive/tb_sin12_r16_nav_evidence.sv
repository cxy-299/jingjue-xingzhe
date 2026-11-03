`timescale 1ns/1ps
module tb_sin12_r16_nav_evidence;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,request=0,av=0,tf=0,ok=1,hard=0,mf=0,cancel=0;
reg [7:0] ab=0,sx=17,sy=2,gx=17,gy=9;
reg [15:0] seq=0,distance=1500;
reg signed [15:0] yaw=0;
reg [31:0] p0=0,p1=0,p2=0,p3=0;
wire active,fault;wire [7:0] state,reason,replans,x,y,ox,oy;wire [2:0] command;
integer n,j,yy,events,first_edge,second_edge,first_ox,first_oy;reg renew=1,emit=1,drive=0,coast=0;
autonomous_nav_guard #(.CELL_COUNTS(333),.NEUTRAL_TICKS(6),.SETTLE_TICKS(3),
 .MAX_TICKS(20000),.LEG_TICKS(2000),.CANCEL_PIPELINE(1),
 .PROGRESS_CONTROL(1),.CONFIRMED_MAPPING(1),.ROUND_POSE_MM(1)) dut(
 .clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(request),.sequence_i(seq),
 .sx_i(sx),.sy_i(sy),.gx_i(gx),.gy_i(gy),.flags_i(8'd1),.speed_i(8'd12),
 .counts_i(16'd333),.setback_i(16'sd0),.yaw_i(yaw),.sensors_ok_i(ok),.hard_stop_i(hard),
 .motor_fault_i(mf),.other_active_i(1'b0),.cancel_i(cancel),.ascii_valid_i(av),.ascii_i(ab),
 .error_i(1'b0),.tof_sample_i(tf),.distance_i(distance),
 .position0_i(p0),.position1_i(p1),.position2_i(p2),.position3_i(p3),
 .active_o(active),.fault_o(fault),.state_o(state),.reason_o(reason),.replans_o(replans),
 .sequence_o(),.x_o(x),.y_o(y),.gx_o(),.gy_o(),.obstacle_x_o(ox),.obstacle_y_o(oy),
 .command_o(command),.speed_o(),.local_mode_o());
task step;begin
 @(negedge clk);tick=0;tf=0;av=0;
 if((drive && command==1)||coast)begin p0=p0+3;p1=p1-3;p2=p2+3;p3=p3-3;end
 if(command==5)begin yy=$signed(yaw)+220;if(yy>25736)yy=yy-51472;yaw=yy;end
 if(command==6)begin yy=$signed(yaw)-220;if(yy< -25736)yy=yy+51472;yaw=yy;end
 repeat(18)@(negedge clk);
 tick=1;tf=emit;av=renew;ab="N";
 @(negedge clk);tick=0;tf=0;av=0;
end endtask
task boot;begin
 rst=0;repeat(5)@(negedge clk);rst=1;
 p0=0;p1=0;p2=0;p3=0;yaw=0;distance=1500;renew=1;emit=1;drive=0;coast=0;
 ok=1;hard=0;mf=0;cancel=0;seq=seq+1;
 repeat(8)step;
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;
 repeat(8)step;
 @(negedge clk);request=1;@(negedge clk);request=0;
 if(!active)$fatal(1,"start rejected reason=%0d",reason);
end endtask
task wait_probe;begin
 n=0;while(active && state!=6 && n<3000)begin step;n=n+1;end
 if(!active || state!=6)$fatal(1,"probe unavailable state=%0d reason=%0d",state,reason);
end endtask
task wait_mark;begin
 n=0;while(active && ox==255 && n<3000)begin step;n=n+1;end
 if(ox==255)$fatal(1,"no confirmed endpoint state=%0d reason=%0d",state,reason);
end endtask
initial begin
 // Actual near face at y=475mm: pivot250 + face offset100 + ray125.
 // Grid y=4. Goal y=9 must neither attract nor clamp this measurement.
 boot;wait_probe;distance=125;wait_mark;
 if(ox!=17 || oy!=4)$fatal(1,"17,2 near ray projected incorrectly %0d,%0d",ox,oy);
 distance=1500;
 n=0;while(active && !(dut.scan_phase==1 && state==6) && n<3000)begin step;n=n+1;end
 if(!active)$fatal(1,"first scan failed reason=%0d",reason);
 repeat(10)step;
 if(ox!=17 || oy!=4)$fatal(1,"far side echo overwrote near block %0d,%0d",ox,oy);
 $display("R16_NAV_START_17_2_GOAL_17_9_OBSTACLE_17_4_FAR_SCAN_NO_PHANTOM_PASS");

 // Incoherent observations never become min-of-unrelated-surfaces occupancy.
 boot;wait_probe;
 for(j=0;j<18;j=j+1)begin distance=j%2?950:175;step;end
 if(ox!=255 || oy!=255 || command)$fatal(1,"unstable range created occupancy or motion");
 emit=0;repeat(110)step;
 if(active || reason!=8 || mf)$fatal(1,"missing stable range misclassified %0d",reason);
 emit=1;distance=125;repeat(20)step;
 if(active || ox!=255)$fatal(1,"late ranges restarted failed job");
 $display("R16_NAV_JITTER_NO_FALSE_MAP_TIMEOUT_NOT_MOTOR_FAULT_PASS");

 // A moving short return stops immediately; do not project it using a later
 // coasted pose. Fresh stopped far returns retain the denied edge, no point.
 boot;drive=1;n=0;
 while(active && !(state==7 && dut.advance>=33) && n<3000)begin step;n=n+1;end
 if(state!=7)$fatal(1,"move unavailable");
 @(negedge clk);distance=300;#1;
 if(command)$fatal(1,"moving near ray did not gate command immediately");
 step;coast=1;distance=1500;emit=0;repeat(9)step;coast=0;
 n=0;while(active && state!=14 && n<100)begin step;n=n+1;end
 if(!active || state!=14 || command)$fatal(1,"not parked for fresh evidence %0d",state);
 if(dut.denied_edges[(y*20+x)*4+0]!=1)$fatal(1,"near edge was not retained");
 repeat(8)step;
 if(ox!=255 || state!=14)$fatal(1,"moving/stale sample became map point");
 emit=1;repeat(6)step;
 if(ox!=255 || oy!=255)$fatal(1,"far stopped return created phantom point");
 distance=1500;n=0;
 while(active && n<12000)begin step;n=n+1;end
 if(state!=11 || fault || x!=17 || y!=9)$fatal(1,"denied-edge replan lost original goal s=%0d e=%0d x=%0d y=%0d",state,reason,x,y);
 $display("R16_NAV_MOVING_NEAR_COAST_REOBSERVE_KEEP_EDGE_REPLAN_ORIGINAL_GOAL_PASS");

 // A coherent near return after braking is projected at its stopped pose.
 boot;drive=1;n=0;
 while(active && !(state==7 && dut.advance>=33) && n<3000)begin step;n=n+1;end
 distance=300;step;emit=0;coast=1;repeat(5)step;coast=0;
 n=0;while(active && state!=14 && n<100)begin step;n=n+1;end
 repeat(8)step;distance=125;emit=1;wait_mark;
 if(ox!=17 || oy!=4)$fatal(1,"brake reobservation used stale ray/origin %0d,%0d",ox,oy);
 $display("R16_NAV_BRAKE_FRESH_NEAR_REPROJECT_SAME_WINDOW_PASS");
 hard=1;#1;if(command)$fatal(1,"hard stop not immediate");step;hard=0;
 if(active || reason!=4)$fatal(1,"hard stop did not terminate");
 // All cardinal directions preserve signed projection (no unsigned wrap).
 for(j=0;j<4;j=j+1)begin
   sx=10;sy=10;gx=j==1?5:j==3?15:10;gy=j==0?15:j==2?5:10;
   boot;wait_probe;distance=250;wait_mark;
   if(ox!=(j==1?7:j==3?14:10) || oy!=(j==0?14:j==2?7:10))
     $fatal(1,"cardinal projection failed direction=%0d point=%0d/%0d",j,ox,oy);
 end
 $display("R16_NAV_FOUR_CARDINAL_SIGNED_PROJECTIONS_PASS");
 sx=1;sy=10;gx=0;gy=10;boot;wait_probe;distance=250;
 n=0;while(active && dut.scan_phase==0 && n<3000)begin step;n=n+1;end
 if(ox!=255 || oy!=255)$fatal(1,"out-of-field ray clamped to false border point");
 $display("R16_NAV_OUTSIDE_FIELD_NO_CLAMP_PASS");
 // A clear one-cell forward leg must consume about 333 counts, not 1000.
 sx=10;sy=2;gx=10;gy=3;boot;drive=1;n=0;
 while(active && n<4000)begin step;n=n+1;end
 if(state!=11 || fault || x!=10 || y!=3 || p0<300 || p0>350)
   $fatal(1,"333-count one-cell leg wrong s=%0d e=%0d pulses=%0d",state,reason,p0);
 $display("R16_STRAIGHT_ONE_CELL_333_COUNTS_PASS pulses=%0d",p0);
 // Encounter TWO added obstacles during the same goal. Neither moving ray
 // becomes a map point: stop, obtain fresh stationary near rays, then replan.
 sx=10;sy=2;gx=10;gy=17;boot;drive=1;events=0;n=0;
 while(active && n<20000)begin
   if(events<2 && state==7 && dut.advance>=33)begin
     @(negedge clk);distance=300;#1;
     if(command)$fatal(1,"new obstacle %0d did not gate motion immediately",events);
     step;emit=0;
     j=0;while(active && state!=14 && j<200)begin step;j=j+1;end
     if(!active || state!=14 || command)$fatal(1,"new obstacle did not park for reobserve");
     if(events==0)first_edge=(y*20+x)*4+dut.blocked_direction;
     else second_edge=(y*20+x)*4+dut.blocked_direction;
     if(!dut.denied_edges[(y*20+x)*4+dut.blocked_direction])$fatal(1,"new edge not denied");
     repeat(8)step;distance=125;emit=1;
     j=0;while(active && state!=9 && j<1000)begin step;j=j+1;end
     if(!active || state!=9)$fatal(1,"fresh new obstacle not projected");
     // MARK publishes endpoint on the following edge.
     repeat(2)step;
     if(events==0)begin first_ox=ox;first_oy=oy;end
     else if(ox==first_ox && oy==first_oy)$fatal(1,"second obstacle reused stale endpoint");
     if(dut.gx_o!=10 || dut.gy_o!=17)$fatal(1,"new obstacle changed mission goal");
     distance=1500;events=events+1;
   end
   step;n=n+1;
 end
 if(events!=2 || state!=11 || fault || x!=10 || y!=17 || replans<2)
   $fatal(1,"two-obstacle task failed ev=%0d s=%0d e=%0d xy=%0d/%0d replan=%0d",events,state,reason,x,y,replans);
 if(!dut.denied_edges[first_edge] || !dut.denied_edges[second_edge])$fatal(1,"old/new denied edge erased");
 $display("R16_TWO_NEW_OBSTACLES_STOP_CONFIRM_REPLAN_SAME_GOAL_PASS");
 $display("SIN12_R16_NAV_EVIDENCE_ALL_PASS");$finish;
end
initial begin #100000000;$fatal(1,"nav evidence test timeout");end
endmodule
