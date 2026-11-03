`timescale 1ns/1ps
module tb_sin12_r6_bridge;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,tick=0,enabled=1,ok=1,hard=0,motor=0,stopped=1,other=0,tf=0,av=0,err=0,nav=0,local_nav=0;
 reg[2:0]cmd=0;reg[7:0]ascii=0,nstate=0;reg[15:0]distance=350;
 wire capture,request,lease,cancel,inhibit;wire[7:0]state,reason;wire[15:0]seq;
 manual_avoid_bridge #(.CONTINUE_ENABLE(1),.QUIET_SAMPLES(3),.LEASE_SAMPLES(8),.START_TIMEOUT(12)) dut(
  .clk(clk),.rst_n(rst),.sample_tick_i(tick),.enabled_i(enabled),.sensors_ok_i(ok),.hard_stop_i(hard),.motor_fault_i(motor),
  .manual_command_i(cmd),.stopped_i(stopped),.other_active_i(other),.tof_sample_i(tf),.distance_i(distance),
  .ascii_valid_i(av),.error_i(err),.ascii_i(ascii),.nav_active_i(nav),.nav_local_i(local_nav),.nav_state_i(nstate),.nav_sequence_i(16'hffff),
  .capture_o(capture),.request_o(request),.sequence_o(seq),.lease_pulse_o(lease),.cancel_o(cancel),.state_o(state),.reason_o(reason),.inhibit_o(inhibit));
 task step;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
 task boot;begin rst=0;distance=350;stopped=1;repeat(3)@(negedge clk);rst=1;cmd=0;av=0;tf=0;hard=0;motor=0;ok=1;other=0;err=0;enabled=1;nav=0;local_nav=0;nstate=0;repeat(3)@(negedge clk);end endtask
 task trigger;begin cmd=1;tf=1;@(negedge clk);tf=0;cmd=0;end endtask
 task byte_cmd(input[7:0]b);begin av=1;ascii=b;@(negedge clk);av=0;end endtask
 task running;begin boot;trigger;repeat(3)step;if(!request || seq!=0)$fatal(1,"request sequence wrap/stable stop");nav=1;local_nav=1;@(negedge clk);if(state!=3)$fatal(1,"owner handshake");end endtask
 integer i;
 initial begin
  boot;cmd=1;repeat(4)step;if(capture)$fatal(1,"stale ToF triggered capture");
  tf=1;av=1;ascii="S";@(negedge clk);tf=0;av=0;cmd=0;repeat(4)step;
  if(capture || request)$fatal(1,"same-cycle S lost to near-ray trigger");
  running;for(i=0;i<20;i=i+1)begin byte_cmd("F");step;end
  if(!capture || cancel)$fatal(1,"held F lease lost");
  // Success is NOT an end of the operator's forward intent.
  nav=0;nstate=11;@(negedge clk);if(state!=6 || !capture)$fatal(1,"missing resume guard");
  distance=900;repeat(3)step;tf=1;@(negedge clk);tf=0;
  if(state!=6)$fatal(1,"resume without renewed F");
  byte_cmd("F");repeat(2)step;if(state!=6)$fatal(1,"stale ToF resumed");
  tf=1;@(negedge clk);tf=0;if(state!=0 || capture || inhibit)$fatal(1,"clear front not returned to manual");
  // Same held trip can capture a second obstacle; no new arm operation.
  distance=350;trigger;repeat(3)step;nav=1;local_nav=1;@(negedge clk);
  if(state!=3)$fatal(1,"second detour failed");
  nav=0;nstate=11;@(negedge clk);byte_cmd("F");repeat(3)step;
  tf=1;@(negedge clk);tf=0;if(state!=1)$fatal(1,"near front blindly resumed manual");
  // Cancellation has priority on the last resume sample, too.
  running;nav=0;nstate=11;@(negedge clk);byte_cmd("F");repeat(3)step;
  distance=900;tf=1;byte_cmd("S");tf=0;if(state!=5 || !inhibit)$fatal(1,"S lost to continuation");
  byte_cmd("F");if(!inhibit)$fatal(1,"streaming F released failed detour");
  byte_cmd("S");if(inhibit)$fatal(1,"explicit S did not reset failed detour");
  running;nav=0;nstate=12;@(negedge clk);if(!inhibit || reason!=7)$fatal(1,"planner failure not latched");
  byte_cmd("F");if(!inhibit)$fatal(1,"F restarted failed planner");
  running;nav=0;nstate=11;@(negedge clk);stopped=0;byte_cmd("F");repeat(3)step;
  distance=900;tf=1;@(negedge clk);tf=0;if(state!=6)$fatal(1,"moving wheels resumed");
  running;repeat(10)step;if(capture || reason!=1)$fatal(1,"lease timeout did not release owner");
  byte_cmd("F");repeat(3)step;if(capture)$fatal(1,"late lease resurrected owner");
  running;ok=0;#1;if(!cancel)$fatal(1,"sensor cancel delayed");@(negedge clk);if(capture || reason!=3)$fatal(1,"sensor cancel state");
  running;hard=1;#1;if(!cancel)$fatal(1,"hard stop cancel delayed");@(negedge clk);if(capture || reason!=4)$fatal(1,"hard stop cancel state");
  running;motor=1;@(negedge clk);if(capture || reason!=8)$fatal(1,"motor cancel state");
  running;other=1;@(negedge clk);if(capture)$fatal(1,"competing owner not canceled");
  running;err=1;@(negedge clk);if(capture || reason!=5)$fatal(1,"framing cancel state");
  running;byte_cmd("B");if(capture)$fatal(1,"reverse did not cancel");
  running;byte_cmd("a");if(capture)$fatal(1,"disable did not cancel");
  boot;trigger;repeat(2)step;av=1;ascii="S";step;av=0;
  if(request || capture)$fatal(1,"same-cycle stop/request escaped");
  boot;trigger;repeat(3)step;
  for(i=0;i<15;i=i+1)begin byte_cmd("F");step;end
  if(capture || reason!=6)$fatal(1,"planner did not accept but owner kept forever");
  $display("R6_CONTINUATION_FRESH_F_TOF_STOP_FAILURE_INHIBIT_PASS");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
