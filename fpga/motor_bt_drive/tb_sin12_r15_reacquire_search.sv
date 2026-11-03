`timescale 1ns/1ps
module tb_sin12_r15_reacquire_search;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,pkt=0,av=0,hard=0,ok=1,cancel=0,still=1,ds=0,fault=0,err=0;
reg selected=1,visible=1,confirmed=1,feed=1,rangefeed=1,renew=1;
reg [7:0] ab=0;reg [15:0] seq=0,pclass=16'hA400;reg [31:0] job=1,pjob=1,lockid=42;reg pred=0;
reg signed [15:0] center=0,yaw=0;reg [15:0] distance=900;
wire active;wire [31:0] id,locked;wire [15:0] cls,speed;wire [4:0] state;wire [2:0] leg,cmd;
vision_mission_guard #(.CLK_HZ(1000),.LEASE_MS(600),.CONTROLLED_ALIGN(1),.MISSION_REFINEMENT(1),
 .PERSISTENT_REACQUIRE(1),.RECOVERY_SEARCH(1),.RECOVERY_RUN_MS(100),
 .RECOVERY_REST_MS(300),.RECOVERY_WAIT_MS(300),.RECOVERY_SPEED(4),.ARRIVAL_TICKS(5)) dut(
 .geometry_frame_i(32'd0),.geometry_valid_i(1'b0),.geometry_beam_i(1'b0),
 .geometry_yaw_i(16'sd0),.geometry_range_i(16'd0),.geometry_uncertainty_i(16'd0),.geometry_age_i(16'd65535),
 .clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.request_id_i(job),.request_class_i(16'hA400),.request_distance_i(16'd300),
 .request_red_i(1'b0),.request_inverted_i(1'b0),.packet_i(pkt),.packet_sequence_i(seq),.packet_mission_i(pjob),
 .packet_lock_i(lockid),.packet_class_i(pclass),.packet_red_i(pred),.selected_i(selected),.visible_i(visible),.confirmed_i(confirmed),
 .center_i(center),.yaw_i(yaw),.distance_i(distance),.distance_sample_i(ds),.sensors_ok_i(ok),.hard_stop_i(hard),.motor_fault_i(fault),
 .other_active_i(1'b0),.cancel_i(cancel),.wheels_still_i(still),.ascii_valid_i(av),.error_i(err),.ascii_i(ab),
 .active_o(active),.id_o(id),.lock_o(locked),.class_o(cls),.state_o(state),.leg_o(leg),.command_o(cmd),.speed_o(speed));
integer cycles=0,n;reg saw_left=0,saw_right=0;
task step;begin
 @(negedge clk);cycles=cycles+1;tick=(cycles%10==0);
 pkt=feed && (cycles%20==0);ds=rangefeed && (cycles%20==0);
 if(pkt)seq=seq+1;
 av=renew && (cycles%50==0);ab="M";
 #1;
 if($isunknown({active,state,cmd,speed}))$fatal(1,"Unknown public control state=%0d",state);
 if(state==17 && cmd!=0)begin
   if(cmd!=5 && cmd!=6)$fatal(1,"Recovery issued a non-rotation command %0d",cmd);
   if(speed>4)$fatal(1,"Recovery exceeded low-speed cap %0d",speed);
   if(cmd==5)saw_left=1;else saw_right=1;
 end
 @(posedge clk);#1;tick=0;pkt=0;av=0;ds=0;
end endtask
task send_packet(input bit is_new);begin
 @(negedge clk);cycles=cycles+1;tick=0;pkt=1;ds=0;av=1;ab="M";
 if(is_new)seq=seq+1;
 #1;
 @(posedge clk);#1;pkt=0;av=0;
end endtask
task boot;begin
 rst=0;repeat(4)@(negedge clk);
 job=32'h12345678;pjob=job;lockid=42;pclass=16'hA400;pred=0;center=0;yaw=0;distance=900;
 selected=1;visible=1;confirmed=1;feed=1;rangefeed=1;renew=1;still=1;hard=0;ok=1;fault=0;err=0;cancel=0;manual_packet_dummy();
 seq=0;cycles=0;saw_left=0;saw_right=0;rst=1;
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;
 repeat(180)step;
 @(negedge clk);req=1;@(negedge clk);req=0;repeat(50)step;
 if(!active || locked!=42)$fatal(1,"R15 setup rejected state=%0d",state);
 n=0;while(active && cmd!=1 && n<2000)begin step;n=n+1;end
 if(!active || cmd!=1)$fatal(1,"Could not establish original approach state=%0d",state);
end endtask
task manual_packet_dummy;begin pkt=0;ds=0;av=0;ab=0;end endtask
task miss;begin
 visible=0;confirmed=0;send_packet(1);
 if(!active || state!=16 || cmd || speed)$fatal(1,"Missing target did not stop and retain original task");
end endtask
task wait_search;begin
 n=0;while(active && state!=17 && n<4000)begin step;n=n+1;end
 if(!active || state!=17 || cmd==0)$fatal(1,"Bounded reacquisition search did not start state=%0d",state);
end endtask
initial begin
 boot;miss;wait_search;
 if(id!=job || locked!=42)$fatal(1,"Search changed original task/token");
 repeat(1700)step;
 if(!active || id!=job || locked!=42)$fatal(1,"Search terminated or replaced task");
 if(!saw_left || !saw_right)$fatal(1,"Search did not alternate both yaw directions L=%0d R=%0d",saw_left,saw_right);
 // A same-lock return cuts search output immediately, then two distinct
 // stopped/fresh observations resume the original mission without a new request.
 still=0;visible=1;confirmed=1;send_packet(1);
 if(cmd || speed)$fatal(1,"Reacquisition did not immediately stop the yaw pulse");
 still=1;repeat(40)step;send_packet(1);repeat(40)step;send_packet(1);
 if(!active || id!=job || locked!=42 || state==16 || state==17)
   $fatal(1,"Same target failed to resume original job state=%0d id=%h lock=%0d",state,id,locked);
 $display("R15_SAME_LOCK_LOSS_BOUNDED_LEFT_RIGHT_SEARCH_REACQUIRE_RESUME_PASS");
 // Near arrival, stale range, hard stop, S and permit loss never authorize search.
 boot;miss;distance=310;repeat(900)step;
 if(!active || state!=16 || cmd || speed)$fatal(1,"Near-arrival recovery rotated instead of waiting");
 $display("R15_NEAR_ARRIVAL_REMAINS_PARKED_PASS");
 boot;miss;wait_search;hard=1;#1;
 if(cmd || speed)$fatal(1,"Hard stop did not gate recovery pulse immediately");
 step; if(active)$fatal(1,"Hard stop did not terminate recovery");
 $display("R15_HARD_STOP_PRECEDENCE_PASS");
 boot;miss;wait_search;av=1;ab="S";#1;
 if(cmd || speed)$fatal(1,"S did not gate recovery pulse immediately");
 @(posedge clk);#1;av=0;
 if(active || state!=12)$fatal(1,"S did not cancel original task");
 $display("R15_S_CANCEL_PRECEDENCE_PASS");
 // Replay the observed417ms host gap repeatedly without extending the
 // absolute600ms firmware deadline. Fresh missing frames retain the task,
 // but are not a substitute for M. No request is re-sent in this sequence.
 boot;miss;distance=310;renew=0;
 repeat(4)begin
   send_packet(1);repeat(417)step;
   if(!active || id!=job || locked!=42 || cmd)
     $fatal(1,"417ms scheduling jitter killed or moved parked original task");
 end
 $display("R15_417MS_LEASE_GAP_TOLERATED_PASS");
 send_packet(1);repeat(599)step;
 if(!active)$fatal(1,"Mission lease expired before600ms");
 repeat(3)step;
 if(active || state!=8 || cmd || speed)$fatal(1,"600ms lease did not expire safely state=%0d",state);
 repeat(5)begin send_packet(1);repeat(30)step;end
 if(active || state!=8 || cmd || speed)$fatal(1,"Late M restarted expired mission");
 $display("R15_600MS_LEASE_EXPIRES_LATE_M_NO_RESTART_PASS");
 $display("SIN12_R15_REACQUIRE_SEARCH_ALL_PASS");$finish;
end
initial begin #20000000;$fatal(1,"R15 simulation timeout");end
endmodule
