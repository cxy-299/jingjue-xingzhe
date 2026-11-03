// R14: actual mission ports, no forced state or internal reference signals.
`timescale 1ns/1ps
module tb_sin12_r14_target_recovery;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,pkt=0,av=0,hard=0,ok=1,cancel=0,still=1,ds=0,fault=0,err=0;
reg selected=1,visible=1,confirmed=1,feed=1,rangefeed=1,renew=1,manual_packet=0,unique_packet=1;
reg[7:0]ab=0;reg[15:0]seq=0,pclass=16'hA400;reg[31:0]job=1,pjob=1,lockid=42;reg pred=0;
reg signed[15:0]center=0,yaw=0;reg[15:0]distance=900;
wire active;wire[31:0]id,locked;wire[15:0]cls,speed;wire[4:0]state;wire[2:0]leg,cmd;
vision_mission_guard #(.CLK_HZ(1000),.CONTROLLED_ALIGN(1),.MISSION_REFINEMENT(1),
 .PERSISTENT_REACQUIRE(1),.ARRIVAL_TICKS(5)) dut(
.geometry_frame_i(32'd0),.geometry_valid_i(1'b0),.geometry_beam_i(1'b0),
.geometry_yaw_i(16'sd0),.geometry_range_i(16'd0),.geometry_uncertainty_i(16'd0),.geometry_age_i(16'd65535),
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.request_id_i(job),.request_class_i(16'hA400),.request_distance_i(16'd300),
.request_red_i(1'b0),.request_inverted_i(1'b0),.packet_i(pkt),.packet_sequence_i(seq),.packet_mission_i(pjob),
.packet_lock_i(lockid),.packet_class_i(pclass),.packet_red_i(pred),.selected_i(selected),.visible_i(visible),.confirmed_i(confirmed),
.center_i(center),.yaw_i(yaw),.distance_i(distance),.distance_sample_i(ds),.sensors_ok_i(ok),.hard_stop_i(hard),.motor_fault_i(fault),
.other_active_i(1'b0),.cancel_i(cancel),.wheels_still_i(still),.ascii_valid_i(av),.error_i(err),.ascii_i(ab),
.active_o(active),.id_o(id),.lock_o(locked),.class_o(cls),.state_o(state),.leg_o(leg),.command_o(cmd),.speed_o(speed));
integer cycles=0,n,k,scenario=0;
task step;begin
 @(negedge clk);cycles=cycles+1;tick=cycles%10==0;
 pkt=manual_packet || (feed && cycles%20==0);ds=rangefeed && cycles%20==0;
 if(pkt && (!manual_packet || unique_packet))seq=seq+1;
 av=renew && cycles%50==0;ab="M";
 #1;if(active && locked!=0 && pkt && (!selected || !visible || !confirmed || lockid!=locked || pjob!=id || pclass!=cls || pred))
   if(cmd || speed)$fatal(1,"Bad observation did not gate motion immediately scenario=%d",scenario);
 @(posedge clk);#1;tick=0;pkt=0;av=0;ds=0;
 if($isunknown({active,state,cmd,speed}))$fatal(1,"Unknown public control scenario=%d",scenario);
end endtask
task send_packet(input bit is_new);begin manual_packet=1;unique_packet=is_new;step;manual_packet=0;end endtask
task boot(input integer number);begin
 scenario=number;rst=0;repeat(4)@(negedge clk);
 job=number;pjob=number;lockid=42;pclass=16'hA400;pred=0;center=0;yaw=0;distance=900;
 selected=1;visible=1;confirmed=1;feed=1;rangefeed=1;renew=1;still=1;hard=0;ok=1;fault=0;err=0;cancel=0;manual_packet=0;seq=0;cycles=0;
 rst=1;@(negedge clk);av=1;ab="S";@(negedge clk);av=0;repeat(180)step;
 @(negedge clk);req=1;@(negedge clk);req=0;repeat(50)step;
 if(!active || locked!=42)$fatal(1,"Boot rejected state=%d scenario=%d",state,scenario);
end endtask
task wait_command(input integer want);begin
 n=0;while(active && cmd!=want && n<2000)begin step;n=n+1;end
 if(!active || cmd!=want)$fatal(1,"Expected command %d got=%d state=%d scenario=%d",want,cmd,state,scenario);
end endtask
task miss;begin
 visible=0;confirmed=0;send_packet(1);
 if(!active || state!=16 || cmd || speed)$fatal(1,"Missing target did not pause scenario=%d state=%d",scenario,state);
end endtask
task terminal(input integer want);begin
 if(active || cmd || speed || state!=want)$fatal(1,"Expected terminal=%d got=%d active=%b scenario=%d",want,state,active,scenario);
end endtask
task assert_wait;begin
 if(!active || state!=16 || cmd || speed)$fatal(1,"Wait moved or terminated scenario=%d state=%d",scenario,state);
end endtask
initial begin
 boot(1);wait_command(1);miss;
 repeat(1300)begin step;assert_wait;end
 if(id!=job || locked!=42)$fatal(1,"Pause changed task identity");
 feed=0;visible=1;confirmed=1;send_packet(1);assert_wait;
 repeat(160)begin step;assert_wait;end
 send_packet(1);if(!active || state==16)$fatal(1,"Second fresh confirmation did not resume");
 feed=1;wait_command(1);
 $display("R14_FIELD_1P3SECOND_SAME_TOKEN_GAP_PAUSE_TWO_NEW_FRAMES_RESUME_PASS");
 // Old replayed observations cannot count as two confirmations or refresh age.
 boot(2);wait_command(1);miss;feed=0;visible=1;confirmed=1;send_packet(1);assert_wait;
 repeat(10)begin repeat(100)step;send_packet(0);assert_wait;end
 repeat(230)step;terminal(9);feed=1;repeat(200)step;terminal(9);
 $display("R14_DUPLICATE_FRAME_NO_RECOVERY_NO_FRESHNESS_LATE_RETURN_NO_RESTART_PASS");
 // Fresh invalid frames keep the SAME active stationary task beyond both
 // the old 4-second deadline and the original 60-second motion budget.
 boot(3);wait_command(1);miss;repeat(65000)begin step;assert_wait;end
 if(id!=job || locked!=42)$fatal(1,"Long wait changed task identity");
 visible=1;confirmed=1;wait_command(1);
 $display("R14_65SECOND_FRESH_MISSING_NO_DEADLINE_SAME_JOB_RESUMES_PASS");
 // Coasting or stale ranging cannot authorize recovery.
 boot(4);wait_command(1);miss;still=0;visible=1;confirmed=1;repeat(300)begin step;assert_wait;end
 rangefeed=0;repeat(270)begin step;assert_wait;end
 still=1;repeat(100)begin step;assert_wait;end
 rangefeed=1;wait_command(1);
 $display("R14_RECONFIRM_REQUIRES_STILL_AND_DISTINCT_FRESH_RANGE_PASS");
 boot(5);wait_command(1);lockid=43;send_packet(1);terminal(14);
 boot(6);wait_command(1);selected=0;send_packet(1);terminal(14);
 boot(7);wait_command(1);pjob=job+1;visible=0;send_packet(1);terminal(12);
 boot(8);wait_command(1);pclass=75;visible=0;send_packet(1);terminal(12);
 boot(9);wait_command(1);pred=1;visible=0;send_packet(1);terminal(12);
 $display("R14_REAL_IDENTITY_SELECTION_MISSION_CLASS_COLOR_CHANGE_TERMINAL_PASS");
 // Every simultaneous safety terminal must win over a recoverable bad frame.
 boot(10);wait_command(1);miss;renew=0;repeat(350)step;terminal(8);
 boot(11);wait_command(1);hard=1;visible=0;send_packet(1);terminal(10);
 boot(12);wait_command(1);fault=1;visible=0;send_packet(1);terminal(10);
 boot(13);wait_command(1);ok=0;visible=0;send_packet(1);terminal(10);
 boot(14);wait_command(1);err=1;visible=0;send_packet(1);terminal(10);
 boot(15);wait_command(1);miss;cancel=1;step;cancel=0;terminal(12);
 boot(16);wait_command(1);miss;@(negedge clk);av=1;ab="S";@(posedge clk);#1;av=0;terminal(12);
 visible=1;confirmed=1;repeat(400)step;terminal(12);
 $display("R14_LEASE_HARDSTOP_MOTOR_SENSOR_ERROR_CANCEL_S_PRECEDENCE_NO_RESTART_PASS");
 // A pause cannot reset the existing side-motion yaw budget.
 boot(17);center=-4500;wait_command(3);miss;visible=1;confirmed=1;yaw=1300;
 repeat(400)step;terminal(15);
 $display("R14_PAUSE_DOES_NOT_RESET_8DEGREE_ALIGNMENT_BUDGET_PASS");
 // Arrival dwell must restart after vision recovery, never count absent frames.
 boot(18);wait_command(1);miss;distance=310;repeat(300)begin step;assert_wait;end
 visible=1;confirmed=1;repeat(220)step;terminal(6);
 $display("R14_NO_FALSE_SUCCESS_DURING_MISSING_TARGET_QUALIFIED_ARRIVAL_PASS");
 $display("SIN12_R14_TARGET_RECOVERY_ALL_PASS");$finish;
end
initial begin #5000000;$fatal(1,"Timeout");end
endmodule

