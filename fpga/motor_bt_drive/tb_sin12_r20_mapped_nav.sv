// Functional primitive-cone evidence. External tick/ToF/position/yaw producers
// are a scaled ideal plant, not a ground measurement or whole-design SDF.
`timescale 1ns/1ps
module tb_sin12_r20_mapped_nav;
GSR GSR(.GSRI(1'b1));
reg clk=0;always #10 clk=~clk;
// n177_5 is the actual active-HIGH primitive CLEAR/PRESET producer.
reg reset=1,key_n=0,tick=0,request=0,av=0,ds=0,emit=1,drive=0;
reg yaw_ok=1,tof_ok=1,hard_event=0;integer minx,miny,maxx,maxy;
reg range854_model=0;integer world_x_counts=8750,world_y_counts=1250,world_x_mm,world_y_mm;
reg [7:0] ascii=0,sx=17,sy=2,gx=17,gy=3,flags=1;
reg [15:0] seq=0,counts=500,distance=1500;
reg signed [15:0] yaw=0;reg signed[15:0] mount_setback=0;
reg [31:0] p0=0,p1=0,p2=0,p3=0;
wire active,faultout,localmode;wire [3:0] state,reason;
// Only actual mapped coordinate bits[7,4:0] exist; bit7 is invalid flag.
wire [15:0] nav_sequence;wire [5:0] x,y,ox,oy;wire [7:0] replans;
wire [4:0] goalx,goaly;wire [2:0] command;
integer n,j,yy,events,firstox,firstoy,last_mark_position;
integer tracking_detour=0,tracked_legs=0,previous_state=0;
integer observed_directions[0:7];
r20_actual_nav dut(.clk(clk),.reset(reset),.key_n(key_n),.tick(tick),.request(request),.seq(seq),
.sx(sx),.sy(sy),.gx(gx),.gy(gy),.counts(counts),.setback(mount_setback),.flags(flags),.velocity(8'd12),
.yaw(yaw),.yawvalid(yaw_ok),.tofvalid(tof_ok),.distance(distance[12:0]),.ds(ds),.hard(hard_event),.fault(2'b00),
.ascii(ascii),.av(av),.err(1'b0),.manual(3'd0),.missionactive(1'b0),.visionactive(1'b0),.turnactive(1'b0),.navactive(1'b0),
.missionrequest(1'b0),.turnrequest(1'b0),.navrequest(1'b0),.avoidrequest(1'b0),.avoidcapture(1'b0),.avoidseq(16'd0),
.p0(p0),.p1(p1),.p2(p2),.p3(p3),.active(active),.faultout(faultout),.state(state),.reason(reason),.\sequence (nav_sequence),
.x(x),.y(y),.goalx(goalx),.goaly(goaly),.ox(ox),.oy(oy),.replans(replans),.localmode(localmode),.command(command));
task step;begin
 @(negedge clk);tick=0;ds=0;av=0;
 if(tracking_detour && state==7 && previous_state!=7)begin
   if(tracked_legs<8)begin
     if($signed(yaw)>10000 && $signed(yaw)<15500)observed_directions[tracked_legs]=1;
     else if($signed(yaw)< -10000 && $signed(yaw)> -15500)observed_directions[tracked_legs]=3;
     else if($signed(yaw)>-2500 && $signed(yaw)<2500)observed_directions[tracked_legs]=0;
     else observed_directions[tracked_legs]=2;
   end
   tracked_legs=tracked_legs+1;
 end
 previous_state=state;
 if(active && x<20 && y<20)begin if(x<minx)minx=x;if(y<miny)miny=y;if(x>maxx)maxx=x;if(y>maxy)maxy=y;end
 if(drive && command==1)begin
  p0=p0+3;p1=p1-3;p2=p2+3;p3=p3-3;
  if(range854_model)begin
   if($signed(yaw)>10000 && $signed(yaw)<15500)world_x_counts=world_x_counts-3;
   else if($signed(yaw)<-10000 && $signed(yaw)>-15500)world_x_counts=world_x_counts+3;
   else if($signed(yaw)>-2500 && $signed(yaw)<2500)world_y_counts=world_y_counts+3;
   else world_y_counts=world_y_counts-3;
  end
 end
 if(range854_model)begin
  world_x_mm=world_x_counts/5;world_y_mm=world_y_counts/5;distance=1500;
  if($signed(yaw)>-2500 && $signed(yaw)<2500 && world_x_mm>=1710 && world_x_mm<=1790 && world_y_mm+104<1208)
   distance=1208-world_y_mm-104;
 end
 if(command==5)begin yy=$signed(yaw)+220;if(yy>25736)yy=yy-51472;yaw=yy;end
 if(command==6)begin yy=$signed(yaw)-220;if(yy< -25736)yy=yy+51472;yaw=yy;end
 repeat(18)@(negedge clk);tick=1;ds=emit;av=1;ascii="N";
 @(negedge clk);tick=0;ds=0;av=0;
end endtask
task boot;begin
 reset=1;key_n=0;request=0;av=0;tick=0;ds=0;drive=0;emit=1;
 p0=0;p1=0;p2=0;p3=0;yaw=0;distance=1500;seq=seq+1;
 yaw_ok=1;tof_ok=1;hard_event=0;minx=sx;maxx=sx;miny=sy;maxy=sy;
 tracking_detour=0;tracked_legs=0;previous_state=0;
 repeat(8)@(negedge clk);key_n=1;
 // The real Timing-optimized queue write CE includes parent ready/key/owner.
 // Keep its actual startup producer and wait >20ms at unchanged 50MHz;
 // do not force ready or replace the shared CE with a guessed input.
 repeat(1000500)@(negedge clk);
 reset=0;
 repeat(25)step;
 @(negedge clk);av=1;ascii="S";@(negedge clk);av=0;repeat(25)step;
 @(negedge clk);request=1;@(negedge clk);request=0;repeat(4)@(negedge clk);
end endtask
task finish_goal;begin
 n=0;while(active && n<30000)begin step;n=n+1;end
 if(active || state!=11 || faultout || x!=gx || y!=gy || command)$fatal(1,"adaptive endpoint failed s%0d e%0d xy%0d,%0d goal%0d,%0d",state,reason,x,y,gx,gy);
end endtask
task obstacle_route(input integer ax,ay,bx,by,range_mm,ex,ey);begin
 sx=ax;sy=ay;gx=bx;gy=by;flags=5;counts=500;boot;n=0;
 while(active && state!=6 && n<6000)begin step;n=n+1;end
 if(state!=6)$fatal(1,"adaptive probe absent");
 distance=range_mm;n=0;while(active && ox==63 && n<6000)begin step;n=n+1;end
 if(ox!=ex || oy!=ey)$fatal(1,"fractional point wrong got%0d,%0d exp%0d,%0d",ox,oy,ex,ey);
 distance=1500;drive=1;finish_goal;
 if(replans!=1)$fatal(1,"unexpected replans%0d",replans);
 if(ax==bx && minx>ax-3 && maxx<ax+3)$fatal(1,"mapped sidestep remained too narrow");
 if(ay==by && miny>ay-3 && maxy<ay+3)$fatal(1,"mapped sidestep remained too narrow");
 $display("R20_MAPPED_NAV_FRACTIONAL_ADAPTIVE_GOAL_PASS range=%0d start%0d,%0d goal%0d,%0d obs%0d,%0d bounds%0d,%0d..%0d,%0d",range_mm,ax,ay,bx,by,ox,oy,minx,miny,maxx,maxy);
end endtask
initial begin
 counts=1000;boot;if(active || reason!=6)$fatal(1,"legacy1000 accepted");
 $display("R20_MAPPED_NAV_LEGACY1000_REJECTED_PASS");
 counts=500;sx=17;sy=2;gx=17;gy=3;flags=1;boot;drive=1;finish_goal;
 if(p0<450 || p0>525)$fatal(1,"500-cell scale wrong pulses%0d",p0);
 $display("R20_MAPPED_NAV_FIXED_MAP_ONE_CELL_500_PASS");
 sx=10;sy=2;gx=10;gy=8;flags=5;boot;drive=1;n=0;
 while(active && !(state==7 && p0>=60) && n<6000)begin step;n=n+1;end
 @(negedge clk);distance=300;#1;if(command!==1)$fatal(1,"300mm prematurely blocked");
 @(negedge clk);distance=200;#1;if(command!==0)$fatal(1,"200mm not immediate");
 repeat(3)@(negedge clk);distance=1500;#1;
 if(state!=8 || command!==0)$fatal(1,"short near event rebounded s%0d cmd%0d",state,command);
 finish_goal;
 $display("R20_MAPPED_NAV_200MM_SUBTICK_STOP_300MM_CLEAR_ORIGINAL_GOAL_PASS");
 obstacle_route(10,5,10,12,200,10,8);
 obstacle_route(10,12,10,5,197,10,9);
 obstacle_route(12,10,5,10,163,9,10);
 obstacle_route(5,10,12,10,163,8,10);
 // Actual calibrated range model: no internal pose or register force.
 sx=17;sy=2;gx=17;gy=17;flags=5;mount_setback=-4;range854_model=1;
 world_x_counts=8750;world_y_counts=1250;boot;drive=1;finish_goal;
 if(replans!=1 || ox!=17 || oy!=12 || minx>14)$fatal(1,"mapped854mm adaptive point or escape wrong r%0d point%0d,%0d minx%0d",replans,ox,oy,minx);
 $display("R20_MAPPED_NAV_854MM_REAL_DISTANCE_GRID12_ADAPTIVE_GOAL_PASS");
 range854_model=0;mount_setback=0;
 // Whole-cell safety can reject a current cell whose rectangular envelope
 // already intersects the safety disk. Never clear it to claim a pass.
 sx=5;sy=10;gx=12;gy=10;flags=5;mount_setback=50;boot;n=0;
 while(active && state!=6 && n<6000)begin step;n=n+1;end
 distance=125;n=0;while(active && n<15000)begin step;n=n+1;end
 if(active || reason!=14 || command || goalx!=12 || goaly!=10)$fatal(1,"unsafe near margin bypassed");
 $display("R20_MAPPED_NAV_CURRENT_CELL_MARGIN_SAFE_STOP_KEEP_GOAL_PASS");
 mount_setback=0;sx=10;sy=2;gx=10;gy=17;flags=5;boot;drive=1;events=0;n=0;
 while(active && n<40000)begin
  if(events==0 && state==7 && command==1 && y>=3)begin
   distance=200;step;emit=0;j=0;while(active && state!=14 && j<300)begin step;j=j+1;end
   if(state!=14 || command)$fatal(1,"first obstacle not parked");
   repeat(8)step;emit=1;j=0;while(active && ox==63 && j<4000)begin step;j=j+1;end
   firstox=ox;firstoy=oy;events=1;distance=1500;
  end
  if(events==1 && state==7 && command==1 && x<=7 && y>=8)begin
   distance=197;step;emit=0;j=0;while(active && state!=14 && j<300)begin step;j=j+1;end
   if(state!=14 || command)$fatal(1,"second obstacle not parked");
   repeat(8)step;emit=1;j=0;while(active && ox==63 && j<4000)begin step;j=j+1;end
   if(ox==firstox && oy==firstoy)$fatal(1,"second obstacle reused stale point");
   events=2;distance=1500;
  end
  step;n=n+1;
 end
 if(events!=2 || state!=11 || x!=10 || y!=17 || goalx!=10 || goaly!=17 || replans!=2 || faultout)$fatal(1,"two obstacle adaptive failed events%0d s%0d e%0d replans%0d",events,state,reason,replans);
 $display("R20_MAPPED_NAV_TWO_NEW_OBSTACLES_ORIGINAL_GOAL_PASS");
 sx=17;sy=2;gx=17;gy=9;flags=1;boot;drive=1;n=0;
 while(active && state!=7 && n<6000)begin step;n=n+1;end
 @(negedge clk);tof_ok=0;#1;if(command)$fatal(1,"ToF loss not immediate");
 @(negedge clk);tof_ok=1;repeat(25)step;
 if(active || reason!=2 || command)$fatal(1,"ToF fault auto resumed");
 $display("R20_MAPPED_NAV_SENSOR_LOSS_E02_NO_RESTART_PASS");
 sx=17;sy=2;gx=17;gy=9;flags=1;boot;drive=1;n=0;
 while(active && state!=7 && n<6000)begin step;n=n+1;end
 @(negedge clk);distance=100;hard_event=1;#1;if(command)$fatal(1,"hard stop delayed");
 @(negedge clk);hard_event=0;distance=1500;repeat(25)step;
 if(active || reason!=4 || command)$fatal(1,"hardstop auto resumed");
 $display("R20_MAPPED_NAV_100MM_HARD_STOP_NO_RESTART_PASS");
 $display("R20_ACTUAL_MAPPED_NAV_PASS");$finish;
end
initial begin #(64'd1000000000);$fatal(1,"mapped adaptive timeout");end
endmodule
