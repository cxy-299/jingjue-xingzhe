`timescale 1ns/1ps
module tb_sin12_r11_mission_refine;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,pkt=0,av=0,hard=0,ok=1,cancel=0,still=1,ds=0;
reg visible=1,feed=1,rangefeed=1,renew=1;
reg[7:0]ab=0;reg[15:0]seq=0;reg[31:0]job=1,lockid=42;
reg signed[15:0]center=0,yaw=0;reg[15:0]distance=900;
wire active;wire[31:0]id,locked;wire[15:0]cls,speed;wire[3:0]state;wire[2:0]leg,cmd;
vision_mission_guard #(.CLK_HZ(1000),.CONTROLLED_ALIGN(1),.MISSION_REFINEMENT(1),.ARRIVAL_TICKS(5)) dut(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.request_id_i(job),.request_class_i(16'd39),.request_distance_i(16'd300),
.request_red_i(1'b0),.request_inverted_i(1'b0),.packet_i(pkt),.packet_sequence_i(seq),.packet_mission_i(job),
.packet_lock_i(lockid),.packet_class_i(16'd39),.packet_red_i(1'b0),.selected_i(1'b1),.visible_i(visible),.confirmed_i(1'b1),
.center_i(center),.yaw_i(yaw),.distance_i(distance),.distance_sample_i(ds),.sensors_ok_i(ok),.hard_stop_i(hard),.motor_fault_i(1'b0),
.other_active_i(1'b0),.cancel_i(cancel),.wheels_still_i(still),.ascii_valid_i(av),.error_i(1'b0),.ascii_i(ab),
.active_o(active),.id_o(id),.lock_o(locked),.class_o(cls),.state_o(state),.leg_o(leg),.command_o(cmd),.speed_o(speed));
integer cycles=0,n,runlength,maxrun,bursts,previous;
task step;begin
 @(negedge clk);cycles=cycles+1;tick=cycles%10==0;pkt=feed && cycles%20==0;ds=rangefeed && cycles%20==0;
 if(pkt)seq=seq+1;av=renew && cycles%50==0;ab="M";
 @(posedge clk);#1;tick=0;pkt=0;av=0;ds=0;
 if($isunknown({active,state,cmd,speed}))$fatal(1,"Unknown control cannot pass");
end endtask
task boot(input integer number);begin
 rst=0;repeat(4)@(negedge clk);rst=1;job=number;lockid=42;center=0;yaw=0;distance=900;
 visible=1;feed=1;rangefeed=1;renew=1;still=1;hard=0;ok=1;cancel=0;cycles=0;
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;repeat(180)step;
 @(negedge clk);req=1;@(negedge clk);req=0;repeat(5)step;
 if(!active)$fatal(1,"New mission failed number=%d state=%d",number,state);
end endtask
task wait_command(input integer want);begin
 n=0;while(active && cmd!=want && n<1500)begin step;n=n+1;end
 if(!active || cmd!=want)$fatal(1,"Expected command %d state=%d got=%d",want,state,cmd);
end endtask
initial begin
 // Real repeated forward pulses must stay bounded, not a continuous drive.
 boot(1);runlength=0;maxrun=0;bursts=0;previous=0;
 repeat(1700)begin
  step;
  if(cmd==1)begin runlength=runlength+1;if(!previous)bursts=bursts+1;if(runlength>maxrun)maxrun=runlength;end
  else runlength=0;
  if(runlength>120)$fatal(1,"Forward move exceeded120ms");previous=cmd;
 end
 if(bursts<2 || maxrun<90)$fatal(1,"Forward motion did not make progress");
 $display("R11_FORWARD120MS_STOP_OBSERVE_REPEAT_PASS bursts=%d max=%d",bursts,maxrun);
 // Approach heading drift belongs to straight control, not a future side step.
 boot(2);wait_command(1);yaw=1500;repeat(180)step;
 if(!active)$fatal(1,"Forward drift incorrectly consumed side heading budget");
 center=-4500;wait_command(3);repeat(2)step;
 if(!active)$fatal(1,"New alignment used old approach heading");
 // The SAME alignment session must retain its budget across STOP/new frames.
 yaw=2200;repeat(200)step;if(!active)$fatal(1,"Small side yaw rejected");
 yaw=2750;repeat(3)step;
 if(active || cmd || state!=15)$fatal(1,"Side session8deg protection weakened");
 $display("R11_APPROACH_AND_LATERAL_EPISODE_HEADING_SEPARATED_NO_PULSE_REZERO_PASS");
 // Three actual distance commits, not repeated sampling of one old register.
 boot(3);rangefeed=0;repeat(400)step;
 if(cmd || !active)$fatal(1,"No fresh range incorrectly moved/terminated");
 rangefeed=1;wait_command(1);rangefeed=0;repeat(260)step;
 if(cmd)$fatal(1,"Old range authorized later step");
 rangefeed=1;wait_command(1);
 distance=430;repeat(65)step;wait_command(1);if(speed>6)$fatal(1,"Near speed not reduced");
 distance=3000;repeat(25)step;
 if(cmd)$fatal(1,"Far range jump continued old motion");
 repeat(50)step;wait_command(1);if(speed>6)$fatal(1,"Far range reaccelerated near approach");
 distance=310;repeat(150)step;
 if(active || state!=6 || cmd)$fatal(1,"Qualified centred arrival failed state=%d",state);
 $display("R11_DISTINCT_RANGE_SAMPLES_EXPIRY_JUMP_STOP_NO_REACCEL_ARRIVAL_PASS");
 // Soft undershoot waits for independent confirmation; raw hard stop never waits.
 boot(4);wait_command(1);distance=260;#1;if(cmd)$fatal(1,"Soft near failed immediate stop");
 repeat(21)step;distance=900;repeat(25)step;
 if(!active)$fatal(1,"One soft outlier ended mission");
 wait_command(1);distance=260;repeat(65)step;
 if(active || cmd || state!=10)$fatal(1,"Consistent close range not stopped");
 boot(5);wait_command(1);hard=1;#1;if(cmd || speed)$fatal(1,"Raw hardstop delayed");step;hard=0;
 if(active || cmd || state!=10)$fatal(1,"Raw hardstop not terminal");
 boot(6);wait_command(1);visible=0;repeat(25)step;
 if(active || cmd || state!=14)$fatal(1,"Target loss allowed motion");
 visible=1;repeat(100)step;if(active || cmd)$fatal(1,"Target return restarted");
 boot(7);wait_command(1);renew=0;repeat(320)step;
 if(active || cmd || state!=8)$fatal(1,"Lease timeout not stopped");
 $display("R11_SOFT_RANGE_CONFIRM_RAW_HARDSTOP_IDENTITY_LEASE_PROTECTION_PASS");
 // Image edge jitter cannot command alternating left/right/forward at once.
 boot(8);center=1300;repeat(100)step;center=0;repeat(100)step;wait_command(1);
 center=1400;repeat(30)step;if(!active)$fatal(1,"Centre hysteresis lost task");
 center=2200;repeat(25)step;if(cmd==1)$fatal(1,"Outer centre limit failed stop");
 cancel=1;#1;if(cmd)$fatal(1,"Cancel physical output delayed");step;cancel=0;
 if(active || cmd || state!=12)$fatal(1,"Cancel not terminal");
 // A new task must not inherit the previous task's speed cap, heading or ID.
 job=9;center=0;distance=900;yaw=8000;
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;repeat(180)step;
 @(negedge clk);req=1;@(negedge clk);req=0;repeat(5)step;wait_command(1);
 if(id!=9 || speed!=8)$fatal(1,"New task inherited old state without FPGA reset");
 feed=0;repeat(400)step;
 if(cmd || !active)$fatal(1,"Missing new visual frame authorised another forward step");
 repeat(850)step;
 if(active || cmd || state!=9)$fatal(1,"Expired visual data not terminal");
 feed=1;repeat(100)step;if(active || cmd)$fatal(1,"Visual return restarted expired task");
 $display("R11_NEW_TASK_NO_RESET_FRESH_VISUAL_TIMEOUT_NO_RESTART_PASS");
 $display("R11_CENTER_HYSTERESIS_AND_ALL_REFINEMENT_REGRESSIONS_PASS");$finish;
end
initial begin #3000000;$fatal(1,"Refinement timeout");end
endmodule
