// Functional primitive-cone evidence. External tick/ToF/position/yaw producers
// are a scaled ideal plant, not a ground measurement or whole-design SDF.
`timescale 1ns/1ps
module tb_sin12_r17_mapped_nav;
GSR GSR(.GSRI(1'b1));
reg clk=0;always #10 clk=~clk;
// n177_5 is the actual active-HIGH primitive CLEAR/PRESET producer.
reg reset=1,key_n=0,tick=0,request=0,av=0,ds=0,emit=1,drive=0;
reg [7:0] ascii=0,sx=17,sy=2,gx=17,gy=3,flags=1;
reg [15:0] seq=0,counts=333,distance=1500;
reg signed [15:0] yaw=0;
reg [31:0] p0=0,p1=0,p2=0,p3=0;
wire active,faultout,localmode;wire [3:0] state,reason;
// Only actual mapped coordinate bits[7,4:0] exist; bit7 is invalid flag.
wire [15:0] nav_sequence;wire [5:0] x,y,ox,oy;wire [7:0] replans;
wire [4:0] goalx,goaly;wire [2:0] command;
integer n,j,yy,events,firstox,firstoy,last_mark_position;
r17_actual_nav dut(.clk(clk),.reset(reset),.key_n(key_n),.tick(tick),.request(request),.seq(seq),
.sx(sx),.sy(sy),.gx(gx),.gy(gy),.counts(counts),.setback(16'd0),.flags(flags),.velocity(8'd12),
.yaw(yaw),.yawvalid(1'b1),.tofvalid(1'b1),.distance(distance[12:0]),.ds(ds),.hard(1'b0),.fault(2'b00),
.ascii(ascii),.av(av),.err(1'b0),.manual(3'd0),.missionactive(1'b0),.visionactive(1'b0),.turnactive(1'b0),.navactive(1'b0),
.missionrequest(1'b0),.turnrequest(1'b0),.navrequest(1'b0),.avoidrequest(1'b0),.avoidcapture(1'b0),.avoidseq(16'd0),
.p0(p0),.p1(p1),.p2(p2),.p3(p3),.active(active),.faultout(faultout),.state(state),.reason(reason),.\sequence (nav_sequence),
.x(x),.y(y),.goalx(goalx),.goaly(goaly),.ox(ox),.oy(oy),.replans(replans),.localmode(localmode),.command(command));
task step;begin
 @(negedge clk);tick=0;ds=0;av=0;
 if(drive && command==1)begin p0=p0+3;p1=p1-3;p2=p2+3;p3=p3-3;end
 if(command==5)begin yy=$signed(yaw)+220;if(yy>25736)yy=yy-51472;yaw=yy;end
 if(command==6)begin yy=$signed(yaw)-220;if(yy< -25736)yy=yy+51472;yaw=yy;end
 repeat(18)@(negedge clk);tick=1;ds=emit;av=1;ascii="N";
 @(negedge clk);tick=0;ds=0;av=0;
end endtask
task boot;begin
 reset=1;key_n=0;request=0;av=0;tick=0;ds=0;drive=0;emit=1;
 p0=0;p1=0;p2=0;p3=0;yaw=0;distance=1500;seq=seq+1;
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
 $display("R17_MAPPED_NAV_LEGACY1000_REJECTED_PASS");
 counts=333;sx=17;sy=2;gx=17;gy=3;flags=1;boot;
 if(!active)$fatal(1,"mapped333 rejected reason=%d",reason);
 drive=1;n=0;while(active && n<6000)begin step;n=n+1;end
 if(state!=11 || faultout || x!=17 || y!=3 || p0<300 || p0>350)
   $fatal(1,"mapped333 one cell wrong state=%d reason=%d xy=%d/%d pulses=%d",state,reason,x,y,p0);
 $display("R17_MAPPED_NAV_FIXED_MAP_ONE_CELL_333_PASS pulses=%d",p0);
 sx=17;sy=2;gx=17;gy=9;flags=1;boot;n=0;
 while(active && state!=6 && n<4000)begin step;n=n+1;end
 if(state!=6)$fatal(1,"mapped probe unavailable state=%d reason=%d",state,reason);
 distance=125;n=0;while(active && ox==63 && n<3000)begin step;n=n+1;end
 if(ox!=17 || oy!=4)$fatal(1,"mapped near ray projection wrong %d/%d state=%d",ox,oy,state);
 $display("R17_MAPPED_NAV_FIXED_MAP_17_2_NEAR_RAY_PROJECTS17_4_PASS");
 // Empty local-map mode isolates successive dynamic obstacles from the fixed
 // map's physical layout. Packet and original goal still use real parent muxes.
 sx=10;sy=2;gx=10;gy=17;flags=5;boot;drive=1;events=0;last_mark_position=0;n=0;
 while(active && n<30000)begin
   if(events<2 && state==7 && command==1 && (p0-last_mark_position)>=33)begin
     @(negedge clk);distance=300;#1;
     if(command!==0)$fatal(1,"mapped near ray failed immediate gate event=%d",events);
     step;emit=0;j=0;while(active && state!=14 && j<300)begin step;j=j+1;end
     if(!active || state!=14 || command)$fatal(1,"mapped obstacle not parked state=%d reason=%d",state,reason);
     repeat(8)step;distance=125;emit=1;j=0;
     while(active && state!=9 && j<1500)begin step;j=j+1;end
     if(!active || state!=9)$fatal(1,"mapped new obstacle evidence not marked state=%d reason=%d",state,reason);
     repeat(2)step;
     if(events==0)begin firstox=ox;firstoy=oy;end
     else if(ox==firstox && oy==firstoy)$fatal(1,"mapped repeated stale obstacle point");
     if(goalx!=10 || goaly!=17)$fatal(1,"mapped obstacle replaced original goal");
     $display("R17_MAPPED_NAV_NEW_OBSTACLE_CONFIRMED event=%d xy=%d/%d",events,ox,oy);
     distance=1500;last_mark_position=p0;events=events+1;
   end
   step;n=n+1;
 end
 if(events!=2 || state!=11 || faultout || x!=10 || y!=17 || replans<2)
   $fatal(1,"mapped successive obstacle mission failed events=%d state=%d reason=%d xy=%d/%d replans=%d",events,state,reason,x,y,replans);
 $display("R17_MAPPED_NAV_TWO_NEW_LOCAL_OBSTACLES_REPLAN_ORIGINAL_GOAL_PASS");
 $display("R17_ACTUAL_MAPPED_NAV_PASS");$finish;
end
initial begin #(64'd500000000);$fatal(1,"mapped nav bench timeout");end
endmodule
