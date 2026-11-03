// Functional primitive-cone evidence. External tick/ToF/position/yaw producers
// are a scaled ideal plant, not a ground measurement or whole-design SDF.
`timescale 1ns/1ps
module tb_sin12_r18_mapped_nav;
GSR GSR(.GSRI(1'b1));
reg clk=0;always #10 clk=~clk;
// n177_5 is the actual active-HIGH primitive CLEAR/PRESET producer.
reg reset=1,key_n=0,tick=0,request=0,av=0,ds=0,emit=1,drive=0;
reg [7:0] ascii=0,sx=17,sy=2,gx=17,gy=3,flags=1;
reg [15:0] seq=0,counts=500,distance=1500;
reg signed [15:0] yaw=0;
reg [31:0] p0=0,p1=0,p2=0,p3=0;
wire active,faultout,localmode;wire [3:0] state,reason;
// Only actual mapped coordinate bits[7,4:0] exist; bit7 is invalid flag.
wire [15:0] nav_sequence;wire [5:0] x,y,ox,oy;wire [7:0] replans;
wire [4:0] goalx,goaly;wire [2:0] command;
integer n,j,yy,events,firstox,firstoy,last_mark_position;
integer tracking_detour=0,tracked_legs=0,previous_state=0;
integer observed_directions[0:7];
r18_actual_nav dut(.clk(clk),.reset(reset),.key_n(key_n),.tick(tick),.request(request),.seq(seq),
.sx(sx),.sy(sy),.gx(gx),.gy(gy),.counts(counts),.setback(16'd0),.flags(flags),.velocity(8'd12),
.yaw(yaw),.yawvalid(1'b1),.tofvalid(1'b1),.distance(distance[12:0]),.ds(ds),.hard(1'b0),.fault(2'b00),
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
 if(drive && command==1)begin p0=p0+3;p1=p1-3;p2=p2+3;p3=p3-3;end
 if(command==5)begin yy=$signed(yaw)+220;if(yy>25736)yy=yy-51472;yaw=yy;end
 if(command==6)begin yy=$signed(yaw)-220;if(yy< -25736)yy=yy+51472;yaw=yy;end
 repeat(18)@(negedge clk);tick=1;ds=emit;av=1;ascii="N";
 @(negedge clk);tick=0;ds=0;av=0;
end endtask
task boot;begin
 reset=1;key_n=0;request=0;av=0;tick=0;ds=0;drive=0;emit=1;
 p0=0;p1=0;p2=0;p3=0;yaw=0;distance=1500;seq=seq+1;
 tracking_detour=0;tracked_legs=0;previous_state=0;
 repeat(8)@(negedge clk);reset=0;key_n=1;
 // The real Timing-optimized queue write CE includes parent ready/key/owner.
 // Keep its actual startup producer and wait >20ms at unchanged 50MHz;
 // do not force ready or replace the shared CE with a guessed input.
 repeat(1000500)@(negedge clk);
 repeat(25)step;
 @(negedge clk);av=1;ascii="S";@(negedge clk);av=0;repeat(25)step;
 @(negedge clk);request=1;@(negedge clk);request=0;repeat(4)@(negedge clk);
end endtask
initial begin
 counts=1000;boot;
 if(active || reason!=6)$fatal(1,"mapped legacy1000 accepted/reason wrong %d",reason);
 $display("R18_MAPPED_NAV_LEGACY1000_REJECTED_PASS");
 counts=500;sx=17;sy=2;gx=17;gy=3;flags=1;boot;
 if(!active)$fatal(1,"mapped500 rejected reason=%d",reason);
 drive=1;n=0;while(active && n<6000)begin step;n=n+1;end
 if(state!=11 || faultout || x!=17 || y!=3 || p0<450 || p0>525)
   $fatal(1,"mapped500 one cell wrong state=%d reason=%d xy=%d/%d pulses=%d",state,reason,x,y,p0);
 $display("R18_MAPPED_NAV_FIXED_MAP_ONE_CELL_500_PASS pulses=%d",p0);
 sx=17;sy=2;gx=17;gy=9;flags=1;boot;n=0;
 while(active && state!=6 && n<4000)begin step;n=n+1;end
 if(state!=6)$fatal(1,"mapped probe unavailable state=%d reason=%d",state,reason);
 distance=125;n=0;while(active && ox==63 && n<3000)begin step;n=n+1;end
 if(ox!=17 || oy!=4)$fatal(1,"mapped near ray projection wrong %d/%d state=%d",ox,oy,state);
 $display("R18_MAPPED_NAV_FIXED_MAP_17_2_NEAR_RAY_PROJECTS17_4_PASS");
 // Read only public command/state/yaw producers. Verify the new three-leg
 // ordering on the actual cone, separately from the two-obstacle interruption.
 sx=10;sy=2;gx=10;gy=8;flags=5;boot;drive=1;n=0;
 while(active && !(state==7 && p0>=60) && n<6000)begin step;n=n+1;end
 @(negedge clk);distance=300;#1;if(command!==0)$fatal(1,"one obstacle not immediate");
 step;distance=1500;tracking_detour=1;previous_state=8;n=0;
 while(active && n<20000)begin step;n=n+1;end
 if(state!=11 || faultout || x!=10 || y!=8 || replans!=1 || tracked_legs<3)
   $fatal(1,"mapped dogleg endpoint failed s%d e%d tracked%d",state,reason,tracked_legs);
 if(observed_directions[0]!=1 || observed_directions[1]!=0 || observed_directions[2]!=3)
   $fatal(1,"mapped dogleg order wrong %d/%d/%d",observed_directions[0],observed_directions[1],observed_directions[2]);
 $display("R18_MAPPED_NAV_LEFT_FORWARD_RIGHT_RESTORE_ORIGINAL_GOAL_PASS");
 tracking_detour=0;
 // Empty local-map mode isolates successive dynamic obstacles from the fixed
 // map's physical layout. Packet and original goal still use real parent muxes.
 sx=10;sy=2;gx=10;gy=17;flags=5;boot;drive=1;events=0;last_mark_position=0;n=0;
 while(active && n<30000)begin
   if(events<2 && state==7 && command==1 && (p0-last_mark_position)>=33)begin
     @(negedge clk);distance=300;#1;
     if(command!==0)$fatal(1,"mapped near ray failed immediate gate event=%d",events);
     step;emit=0;j=0;while(active && state!=14 && j<300)begin step;j=j+1;end
     if(!active || state!=14 || command)$fatal(1,"mapped obstacle not parked state=%d reason=%d",state,reason);
     repeat(8)step;distance=300;emit=1;j=0;
     while(active && state!=9 && j<1500)begin step;j=j+1;end
     if(!active || state!=9)$fatal(1,"mapped new obstacle evidence not marked state=%d reason=%d",state,reason);
     repeat(2)step;
     if(events==0)begin firstox=ox;firstoy=oy;end
     else if(ox==firstox && oy==firstoy)$fatal(1,"mapped repeated stale obstacle point");
     if(goalx!=10 || goaly!=17)$fatal(1,"mapped obstacle replaced original goal");
     $display("R18_MAPPED_NAV_NEW_OBSTACLE_CONFIRMED event=%d xy=%d/%d",events,ox,oy);
     distance=1500;last_mark_position=p0;events=events+1;
   end
   step;n=n+1;
 end
 if(events!=2 || state!=11 || faultout || x!=10 || y!=17 || replans<2)
   $fatal(1,"mapped successive obstacle mission failed events=%d state=%d reason=%d xy=%d/%d replans=%d",events,state,reason,x,y,replans);
 $display("R18_MAPPED_NAV_TWO_NEW_LOCAL_OBSTACLES_LEFT_DETOUR_ORIGINAL_GOAL_PASS");
 $display("R18_ACTUAL_MAPPED_NAV_PASS");$finish;
end
initial begin #(64'd600000000);$fatal(1,"mapped nav bench timeout");end
endmodule
