// Actual production 50MHz mapped cone: no force, no changed FF initialization.
// sample_tick is a public producer interface. The final expiry subtest emits
//400 accelerated external strobes to check counter logic, not elapsed wall time.
`timescale 1ns/1ps
module tb_sin12_r13_mapped_recovery;
GSR GSR(.GSRI(1'b1));
reg clk=0;always #10 clk=~clk;
reg reset=1,tick=0,request=0,pkt=0,visible=1,confirmed=1,selected=1,ds=0;
reg[15:0]seq=0;reg[7:0]ascii=0;reg av=0,feed=1,renew=1,fast_tick=0;
reg[31:0]lockid=42;reg[12:0]distance=900;
wire active;wire[4:0]state;wire[31:0]id,locked;wire[2:0]command;
integer cycles=0,n;reg manual_av=0;reg[7:0]manual_ascii=0;reg manual_pkt=0;
r13_actual_recovery dut(.clk(clk),.reset(reset),.tick(tick),.request(request),.job(32'h8c3d63c2),.cls(16'd39),.arrival(10'd300),
.red(1'b0),.inv(1'b0),.pkt(pkt),.seq(seq),.pjob(32'h8c3d63c2),.lockid(lockid),.pclass(16'd39),.pred(1'b0),
.selected(selected),.visible(visible),.confirmed(confirmed),.center(16'd0),.yaw(16'd0),.distance(distance),.ds(ds),
.yawvalid(1'b1),.tofvalid(1'b1),.hard(1'b0),.fault(2'b00),.ascii(ascii),.av(av),.err(1'b0),.manual(3'd0),
.autoactive(1'b0),.visionactive(1'b0),.turnactive(1'b0),.navactive(1'b0),.autorequest(1'b0),.turnrequest(1'b0),.navrequest(1'b0),
.vcommand(3'bxxx),.tcommand(3'bxxx),.ncommand(3'bxxx),
.wheel0(16'd0),.wheel1(16'd0),.wheel2(16'd0),.wheel3(16'd0),
.active(active),.state(state),.id(id),.locked(locked),.command(command));
always @(negedge clk)begin
 cycles=cycles+1;
 tick=fast_tick ? cycles%4==0 : cycles%500000==0;
 ds=cycles%500000==0;
 pkt=manual_pkt || (feed && cycles%500000==0);
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
 clocks(8);reset=0;clocks(8);manual_av=1;manual_ascii="S";clocks(3);manual_av=0;
 packet;clocks(7500100); // Real 150ms neutral startup at unchanged 50MHz.
 @(negedge clk);request=1;clocks(2);request=0;clocks(20);
 if(active!==1 || locked!==42)$fatal(1,"Mapped request/lock failed state=%d",state);
 n=0;while(command!==1 && n<10000000)begin clocks(1000);n=n+1000;end
 if(command!==1)$fatal(1,"Mapped original mission never approached state=%d",state);
 $display("R13_MAPPED_ORIGINAL_INTERFACE_REQUEST_AND_FORWARD_PASS");
 visible=0;confirmed=0;packet;waiting;
 clocks(7500200);waiting; // Real >=150ms neutral after a visibility miss.
 feed=0;visible=1;confirmed=1;packet;waiting;
 // Existing independent range strobes continue every real10ms; second new
 // confirmed observation resumes the SAME ID, never another request pulse.
 clocks(1000000);packet;
 if(active!==1 || state===16 || id!==32'h8c3d63c2 || locked!==42)$fatal(1,"Mapped second confirmation did not resume state=%d",state);
 feed=1;n=0;while(command!==1 && n<10000000)begin clocks(1000);n=n+1000;end
 if(command!==1)$fatal(1,"Mapped resumed mission did not approach state=%d",state);
 $display("R13_MAPPED_PAUSE_TWO_NEW_CONFIRMATIONS_SAME_TASK_AUTO_CONTINUE_PASS");
 // Invalid fresh updates cannot reset the400-tick recovery deadline.
 visible=0;confirmed=0;packet;waiting;feed=0;fast_tick=1;
 repeat(34)begin clocks(40);packet;waiting;end
 clocks(200);
 if(active!==0 || state!==14 || command!==0)$fatal(1,"Mapped400-tick deadline failed state=%d",state);
 visible=1;confirmed=1;repeat(4)begin packet;clocks(50);end
 if(active!==0 || state!==14 || command!==0)$fatal(1,"Mapped terminal auto-restarted");
 $display("R13_MAPPED_400_SAMPLE_DEADLINE_BAD_UPDATES_NO_REFRESH_LATE_RETURN_NO_RESTART_PASS");
 $display("R13_ACTUAL_MAPPED_RECOVERY_PASS");$finish;
end
initial begin #1000000000;$fatal(1,"Mapped test timeout");end
endmodule

