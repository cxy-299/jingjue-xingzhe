// Supplement: real50MHz continuous quiet negative/boundary cases; search
// interval externally accelerated, asserted as sample-strobe contract only.
// Actual production 50MHz mapped cone: no force, no changed FF initialization.
// sample_tick is a public producer interface. The long-pause subtest emits
//6500 accelerated external strobes; not65s elapsed50MHz wall time.
// reset is the REAL active-low top-level key_s0_n input, no internal reset cut.
`timescale 1ns/1ps
module tb_sin12_r17_mapped_settle;
GSR GSR(.GSRI(1'b1));
reg [15:0] wheel=0;
reg settle_tracking=0,last_yaw_motion=0;
integer quiet_ticks=0,pulse_ticks=0,tracked_pulses=0;
reg clk=0;always #10 clk=~clk;
reg reset=1,key_n=0,tick=0,request=0,pkt=0,visible=1,confirmed=1,selected=1,ds=0;
reg[15:0]seq=0;reg[7:0]ascii=0;reg av=0,feed=1,renew=1,fast_tick=0;
reg[31:0]lockid=42;reg[12:0]distance=900;
wire active;wire[4:0]state;wire[31:0]id,locked;wire[2:0]command;
integer cycles=0,n;reg manual_av=0;reg[7:0]manual_ascii=0;reg manual_pkt=0;
reg search_samples=0,saw_left=0,saw_right=0;
always @(posedge clk) begin
 if(settle_tracking) begin
  if(command==5 || command==6)begin
   if(!last_yaw_motion)begin
    if(quiet_ticks<100)$fatal(1,"Mapped search interval below100 external10ms ticks: %d",quiet_ticks);
    tracked_pulses=tracked_pulses+1;
   end
   quiet_ticks=0;
   if(tick)pulse_ticks=pulse_ticks+1;
   if(pulse_ticks>11)$fatal(1,"Mapped search pulse exceeded external100ms contract");
  end else begin
   if(tick)quiet_ticks=quiet_ticks+1;
   pulse_ticks=0;
  end
  last_yaw_motion=(command==5 || command==6);
 end
end
always @(posedge clk)if(state===17)begin
 if(command===5)saw_left<=1;
 if(command===6)saw_right<=1;
end
r17_actual_recovery dut(.clk(clk),.reset(reset),.key_n(key_n),.tick(tick),.request(request),.job(32'h8c3d63c2),.cls(16'hA400),.arrival(10'd300),
.red(1'b0),.inv(1'b0),.pkt(pkt),.seq(seq),.pjob(32'h8c3d63c2),.lockid(lockid),.pclass(16'hA400),.pred(1'b0),
.selected(selected),.visible(visible),.confirmed(confirmed),.center(16'd0),.yaw(16'd0),.distance(distance),.ds(ds),
.yawvalid(1'b1),.tofvalid(1'b1),.hard(1'b0),.fault(2'b00),.ascii(ascii),.av(av),.err(1'b0),.manual(3'd0),
.autoactive(1'b0),.visionactive(1'b0),.turnactive(1'b0),.navactive(1'b0),.autorequest(1'b0),.turnrequest(1'b0),.navrequest(1'b0),
.vcommand(3'bxxx),.tcommand(3'bxxx),.ncommand(3'bxxx),
.wheel0(wheel),.wheel1(wheel),.wheel2(wheel),.wheel3(wheel),
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
initial begin
 clocks(8);reset=0;key_n=1;clocks(8);manual_av=1;manual_ascii="S";clocks(3);manual_av=0;
 packet;clocks(7500100); // Real 150ms neutral startup at unchanged 50MHz.
 @(negedge clk);request=1;clocks(2);request=0;clocks(20);
 if(active!==1 || locked!==42)$fatal(1,"Mapped request/lock failed state=%d",state);
 n=0;while(command!==1 && n<10000000)begin clocks(1000);n=n+1000;end
 if(command!==1)$fatal(1,"Mapped original mission never approached state=%d",state);
 $display("R17_MAPPED_ORIGINAL_INTERFACE_REQUEST_AND_FORWARD_PASS");
 visible=0;confirmed=0;packet;waiting;
 clocks(51000200);waiting; // Real >=1020ms settling after a visibility miss.
 feed=0;visible=1;confirmed=1;packet;waiting;
 // Existing independent range strobes continue every real10ms; second new
 // confirmed observation resumes the SAME ID, never another request pulse.
 clocks(1000000);packet;
 if(active!==1 || state===16 || id!==32'h8c3d63c2 || locked!==42)$fatal(1,"Mapped second confirmation did not resume state=%d",state);
 feed=1;n=0;while(command!==1 && n<10000000)begin clocks(1000);n=n+1000;end
 if(command!==1)$fatal(1,"Mapped resumed mission did not approach state=%d",state);
 $display("R17_MAPPED_PAUSE_TWO_NEW_CONFIRMATIONS_SAME_TASK_AUTO_CONTINUE_PASS");
 // 6500 accelerated EXTERNAL 10ms strobes: no old400-sample timeout.
 // This is a sample-interface contract, not65s of50MHz simulated time.
 distance=310;visible=0;confirmed=0;packet;waiting;feed=0;fast_tick=1;
 repeat(650)begin clocks(40);packet;waiting;end
 $display("R17_MAPPED_6500_FRESH_MISSING_SAMPLES_PERSIST_ORIGINAL_ID_ZERO_OUTPUT_PASS");
 fast_tick=0;feed=1;distance=900;clocks(51000200);visible=1;confirmed=1;
 feed=0;packet;waiting;clocks(1000000);packet;
 if(active!==1 || state===16 || id!==32'h8c3d63c2 || locked!==42)$fatal(1,"Mapped long-pause did not resume original task");
 $display("R17_MAPPED_LONG_PAUSE_RECONFIRM_ORIGINAL_TASK_PASS");
 // The actual mapped search cone is exercised without modifying any FF or
 // constants. Only external sample/range/frame producer strobes are sped up;
 // this is NOT a real100ms pulse-duration or physical-yaw plant test.
 settle_tracking=1;visible=0;confirmed=0;packet;waiting;fast_tick=1;search_samples=1;feed=1;
 wait(saw_left && saw_right);clocks(1);
 if(tracked_pulses<2)$fatal(1,"Insufficient mapped search pulse intervals");
 $display("R17_MAPPED_SETTLE_SEARCH1000MS_INTERVAL_EXTERNAL_TICK_CONTRACT_PASS");
 settle_tracking=0;
 if(active!==1 || id!==32'h8c3d63c2 || locked!==42)
   $fatal(1,"Mapped bounded search changed task or identity");
 visible=1;confirmed=1;packet;
 if(command!==0)$fatal(1,"Mapped original target return did not cut yaw output");
 fast_tick=0;search_samples=0;feed=0;clocks(51000200);packet;clocks(1000000);packet;
 if(active!==1 || state===16 || state===17 || id!==32'h8c3d63c2 || locked!==42)
   $fatal(1,"Mapped search did not return to original mission state=%d",state);
 $display("R17_MAPPED_ACCELERATED_EXTERNAL_STROBES_LEFT_RIGHT_SAME_TASK_REACQUIRE_PASS");
 // Coasting input is a real wheel-speed producer, never an internal force.
 wheel=16'd5;visible=0;confirmed=0;packet;waiting;
 feed=1;visible=1;confirmed=1;packet;clocks(3000000);waiting;
 $display("R17_MAPPED_SETTLE_MOVING_WHEELS_BLOCK_FRESH_CONFIRMATIONS_PASS");
 wheel=0;clocks(45000000);waiting; // 900ms is not a full stationary second.
 $display("R17_MAPPED_SETTLE_900MS_AFTER_COAST_CANNOT_RESUME_PASS");
 clocks(7000000); // Total1040ms: >=101 new real10ms quiet samples.
 if(active!==1 || state===16 || state===17 || id!==32'h8c3d63c2 || locked!==42)
   $fatal(1,"Mapped new quiet second/fresh frames failed original-task resume state=%d",state);
 $display("R17_MAPPED_SETTLE_1040MS_AND_NEW_FRAMES_RESUME_ORIGINAL_TASK_PASS");
 manual_av=1;manual_ascii="S";clocks(3);manual_av=0;clocks(5);
 if(active!==0 || command!==0)$fatal(1,"Mapped S failed");
 feed=1;clocks(1000000);
 if(active!==0 || command!==0)$fatal(1,"Mapped S restarted");
 $display("R17_MAPPED_S_CANCEL_REMAINS_TERMINAL_PASS");
 $display("R17_ACTUAL_MAPPED_SETTLE_PASS");$finish;
end
initial begin #(64'd8000000000);$fatal(1,"Mapped test timeout");end
endmodule
