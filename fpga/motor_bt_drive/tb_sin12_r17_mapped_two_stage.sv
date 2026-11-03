// Actual production 50MHz mapped cone: no force, no changed FF initialization.
// sample_tick is a public producer interface. The long-pause subtest emits
//6500 accelerated external strobes; not65s elapsed50MHz wall time.
// reset is the REAL active-low top-level key_s0_n input, no internal reset cut.
`timescale 1ns/1ps
module tb_sin12_r17_mapped_two_stage;
GSR GSR(.GSRI(1'b1));
reg clk=0;always #10 clk=~clk;
reg reset=1,key_n=0,tick=0,request=0,pkt=0,visible=1,confirmed=1,selected=1,ds=0;
reg[15:0]seq=0;reg[7:0]ascii=0;reg av=0,feed=1,renew=1,fast_tick=0;
reg[31:0]lockid=42;reg[12:0]distance=900;
reg signed[15:0] center=0,yaw=0;
wire active;wire[4:0]state;wire[31:0]id,locked;wire[2:0]command;
integer cycles=0,n;reg manual_av=0;reg[7:0]manual_ascii=0;reg manual_pkt=0;
reg search_samples=0,saw_left=0,saw_right=0;
always @(posedge clk)if(state===17)begin
 if(command===5)saw_left<=1;
 if(command===6)saw_right<=1;
end
r17_actual_recovery dut(.clk(clk),.reset(reset),.key_n(key_n),.tick(tick),.request(request),.job(32'h8c3d63c2),.cls(16'hA400),.arrival(10'd300),
.red(1'b0),.inv(1'b0),.pkt(pkt),.seq(seq),.pjob(32'h8c3d63c2),.lockid(lockid),.pclass(16'hA400),.pred(1'b0),
.selected(selected),.visible(visible),.confirmed(confirmed),.center(center),.yaw(yaw),.distance(distance),.ds(ds),
.yawvalid(1'b1),.tofvalid(1'b1),.hard(1'b0),.fault(2'b00),.ascii(ascii),.av(av),.err(1'b0),.manual(3'd0),
.autoactive(1'b0),.visionactive(1'b0),.turnactive(1'b0),.navactive(1'b0),.autorequest(1'b0),.turnrequest(1'b0),.navrequest(1'b0),
.vcommand(3'bxxx),.tcommand(3'bxxx),.ncommand(3'bxxx),
.wheel0(16'd0),.wheel1(16'd0),.wheel2(16'd0),.wheel3(16'd0),
.active(active),.state(state),.id(id),.locked(locked),.command(command));
always @(negedge clk)begin
 cycles=cycles+1;
 tick=fast_tick ? cycles%4==0 : cycles%500000==0;
 ds=search_samples ? cycles%4==0 : cycles%500000==0;
 pkt=manual_pkt || (feed && (search_samples ? cycles%20==0 : cycles%500000==0));
 if(pkt)seq=seq+1;
 av=manual_av || (renew && cycles%2000000==0);ascii=manual_av?manual_ascii:"M";
end
task clocks(input integer count);begin repeat(count)@(posedge clk);#1;end endtask
// Exactly one new packet pulse: do not accidentally count two confirmations.
task packet;begin @(posedge clk);#1;manual_pkt=1;@(posedge clk);#1;manual_pkt=0;clocks(1);end endtask
task waiting;begin
 if(active!==1 || state!==16 || command!==0 || id!==32'h8c3d63c2 || locked!==42)
 $fatal(1,"Mapped WAIT invalid active=%b state=%d cmd=%d id=%h lock=%d",active,state,command,id,locked);
end endtask
task boot;begin
 reset=1;key_n=0;request=0;manual_av=0;manual_pkt=0;visible=1;confirmed=1;feed=1;renew=1;fast_tick=0;search_samples=0;distance=900;center=0;yaw=0;
 clocks(8);reset=0;key_n=1;clocks(8);manual_av=1;manual_ascii="S";clocks(3);manual_av=0;
 packet;clocks(7500100);
 @(negedge clk);request=1;clocks(2);request=0;clocks(20);
 n=0;while(command!==1 && n<10000000)begin clocks(1000);n=n+1000;end
 if(active!==1 || command!==1 || locked!==42)$fatal(1,"two-stage original request failed state=%d",state);
end endtask
initial begin
 boot;
 // No internal sample acceleration in this supplement:650ms=32.5M clocks.
 repeat(32500)begin clocks(1000);if(command!==1)$fatal(1,"coarse output pulsed with fresh target state=%d",state);end
 $display("R17_MAPPED_TWO_STAGE_REAL650MS_CONTINUOUS_COARSE_PASS");
 distance=400;#1;if(command!==0)$fatal(1,"arrival+100mm did not cut coarse forward immediately");
 repeat(45000)begin clocks(1000);if(command!==0)$fatal(1,"900ms park incorrectly resumed fine phase");end
 n=0;while(command!==1 && n<15000000)begin clocks(1000);n=n+1000;end
 if(command!==1 || active!==1)$fatal(1,"fresh parked handoff did not authorize fine step state=%d",state);
 n=0;while(command===1 && n<3100000)begin clocks(1000);n=n+1000;end
 if(command!==0 || n>3000000 || n<1000)$fatal(1,"fine step exceeded60ms n=%d",n);
 $display("R17_MAPPED_TWO_STAGE_HANDOFF100MM_REAL_PARK_FINE60MS_PASS");
 distance=900;n=0;
 // Far background may not turn a sticky final phase back into continuous drive.
 repeat(30000)begin clocks(1000);if(command===1)n=n+1000;else n=0;
   if(n>3000000)$fatal(1,"far echo reset final phase into coarse drive");end
 $display("R17_MAPPED_TWO_STAGE_FINAL_PHASE_FAR_ECHO_NO_COARSE_RETURN_PASS");
 boot;center=2500;packet;n=0;
 while(command!==5 && command!==6 && n<70000000)begin clocks(1000);n=n+1000;
   if(command===3 || command===4)$fatal(1,"smart alignment issued lateral command");end
 if(command!==6)$fatal(1,"bounded yaw alignment unavailable state=%d",state);
 n=0;while(command!==0 && n<3100000)begin clocks(1000);n=n+1000;end
 if(command!==0 || n>3000000)$fatal(1,"yaw alignment exceeded60ms");
 yaw=1300;clocks(20);
 if(active!==0 || state!==15 || command!==0)$fatal(1,"original8degree fault not enforced state=%d",state);
 $display("R17_MAPPED_TWO_STAGE_YAW_ONLY60MS_ORIGINAL8DEG_PASS");
 boot;manual_av=1;manual_ascii="S";clocks(3);manual_av=0;clocks(1000);
 if(active!==0 || command!==0)$fatal(1,"mapped S did not terminate");
 $display("R17_MAPPED_TWO_STAGE_S_TERMINAL_PASS");
 $display("R17_ACTUAL_MAPPED_TWO_STAGE_PASS");$finish;
end
initial begin #(64'd12000000000);$fatal(1,"mapped two-stage test timeout");end
endmodule
