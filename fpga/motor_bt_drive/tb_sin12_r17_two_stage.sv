`timescale 1ns/1ps
module tb_sin12_r17_two_stage;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,pkt=0,av=0,hard=0,ok=1,cancel=0,still=1,ds=0,fault=0,err=0;
reg selected=1,visible=1,confirmed=1,feed=1,rangefeed=1,renew=1;
reg [7:0] ab=0;reg [15:0] seq=0,pclass=16'hA400;reg [31:0] job=1,pjob=1,lockid=42;reg pred=0;
reg signed [15:0] center=0,yaw=0;reg [15:0] distance=900;
wire active;wire [31:0] id,locked;wire [15:0] cls,speed;wire [4:0] state;wire [2:0] leg,cmd;
vision_mission_guard #(.CLK_HZ(1000),.LEASE_MS(600),.CONTROLLED_ALIGN(1),.MISSION_REFINEMENT(1),
 .PERSISTENT_REACQUIRE(1),.RECOVERY_SEARCH(1),.RECOVERY_RUN_MS(100),
 .RECOVERY_REST_MS(1000),.RECOVERY_WAIT_MS(1000),.OBSERVE_SETTLE_MS(1000),.ALIGN_REST_MS(1000),.APPROACH_REST_MS(300),.RECOVERY_SPEED(4),.ARRIVAL_TICKS(5),.TWO_STAGE_APPROACH(1)) dut(
 .geometry_frame_i(32'd0),.geometry_valid_i(1'b0),.geometry_beam_i(1'b0),
 .geometry_yaw_i(16'sd0),.geometry_range_i(16'd0),.geometry_uncertainty_i(16'd0),.geometry_age_i(16'd65535),
 .clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.request_id_i(job),.request_class_i(16'hA400),.request_distance_i(16'd300),
 .request_red_i(1'b0),.request_inverted_i(1'b0),.packet_i(pkt),.packet_sequence_i(seq),.packet_mission_i(pjob),
 .packet_lock_i(lockid),.packet_class_i(pclass),.packet_red_i(pred),.selected_i(selected),.visible_i(visible),.confirmed_i(confirmed),
 .center_i(center),.yaw_i(yaw),.distance_i(distance),.distance_sample_i(ds),.sensors_ok_i(ok),.hard_stop_i(hard),.motor_fault_i(fault),
 .other_active_i(1'b0),.cancel_i(cancel),.wheels_still_i(still),.ascii_valid_i(av),.error_i(err),.ascii_i(ab),
 .active_o(active),.id_o(id),.lock_o(locked),.class_o(cls),.state_o(state),.leg_o(leg),.command_o(cmd),.speed_o(speed));
integer cycles=0,n;reg saw_left=0,saw_right=0;
integer quiet_clocks=0,pulse_clocks=0;reg tracking=0,last_motion=0;
always @(posedge clk)begin
 if(!rst || !tracking)begin quiet_clocks=0;pulse_clocks=0;last_motion=0;end
 else begin
   if(cmd!=0)begin
     if(!last_motion && cmd!=1 && quiet_clocks<1000)$fatal(1,"R16 motion restarted before1000ms quiet: %0d",quiet_clocks);
     pulse_clocks=pulse_clocks+1;
     if(state==17 && pulse_clocks>101)$fatal(1,"R16 yaw pulse exceeded100ms");
     quiet_clocks=0;
   end else begin quiet_clocks=quiet_clocks+1;pulse_clocks=0;end
   last_motion=(cmd!=0);
 end
end
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
 if(!active || locked!=42)$fatal(1,"R16 setup rejected state=%0d",state);
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
 // CLK_HZ1000 is a counter-unit accelerated model, not physical timing/SDF.
 boot;still=0;repeat(650)begin step;if(cmd!=1 || speed>8 || speed==0)$fatal(1,"coarse approach pulsed/lost guard state=%0d cmd=%0d",state,cmd);end
 $display("R17_COARSE_FRESH_650MS_CONTINUOUS_PASS");
 // Crossing is live-gated before the sticky handoff and cannot reaccelerate
 // if a later background range jumps farther away.
 distance=400;#1;if(cmd!=0)$fatal(1,"coarse boundary was not gated immediately");
 still=1;repeat(900)begin step;if(cmd)$fatal(1,"fine move before complete parked second");end
 n=0;while(cmd!=1 && n<800)begin step;n=n+1;end
 if(!active || cmd!=1 || speed>4 || !dut.two_stage_final)$fatal(1,"fine handoff failed state=%0d",state);
 n=0;while(cmd==1 && n<80)begin step;n=n+1;end
 if(n>60 || cmd || !dut.two_stage_final)$fatal(1,"fine pulse too long n=%0d",n);
 $display("R17_HANDOFF100MM_PARK_FRESH_FRAMES_FINE60MS_PASS");
 distance=900;repeat(100)step;
 if(!dut.two_stage_final || speed>4)$fatal(1,"far echo reset final stage/speed");
 $display("R17_FINAL_PHASE_STICKY_FAR_BACKGROUND_NO_ACCEL_PASS");
 // Alignment is bounded yaw, never lateral3/4, and original8degree budget wins.
 boot;center=2500;n=0;
 while(cmd!=5 && cmd!=6 && n<2500)begin step;if(cmd==3 || cmd==4)$fatal(1,"R17 lateral alignment survived");n=n+1;end
 if(cmd!=6 || speed>4)$fatal(1,"yaw alignment direction/speed wrong cmd=%0d",cmd);
 n=0;while(cmd!=0 && n<80)begin step;n=n+1;end
 if(n>60)$fatal(1,"yaw alignment exceeded60ms");
 yaw=1300;repeat(8)step;
 if(active || state!=15 || cmd)$fatal(1,"original8degree heading protection weakened");
 $display("R17_YAW_ONLY_LOW_SPEED_60MS_ORIGINAL8DEG_PASS");
 // No missed/stale frame may authorize blind approach or change original token.
 boot;miss;repeat(100)step;
 if(!active || cmd || id!=job || locked!=42)$fatal(1,"miss did not park retained task");
 visible=1;confirmed=1;repeat(1400)step;
 if(!active || id!=job || locked!=42 || state==16 || state==17)$fatal(1,"same-token recovery failed");
 $display("R17_SAME_TARGET_MISS_PARK_AND_RESUME_PASS");
 boot;hard=1;#1;if(cmd)$fatal(1,"hard stop was not immediate");step;
 if(active || state!=10)$fatal(1,"hard stop not terminal");
 boot;fault=1;#1;if(cmd)$fatal(1,"motor fault not immediate");step;
 if(active || state!=10)$fatal(1,"motor fault not terminal");
 boot;av=1;ab="S";@(posedge clk);#1;av=0;
 if(active || cmd || state!=12)$fatal(1,"S not terminal");
 $display("R17_HARD_STOP_MOTOR_FAULT_S_PRECEDENCE_PASS");
 boot;distance=320;still=1;repeat(1500)step;
 if(active || state!=6 || cmd)$fatal(1,"arrival was not completed while parked state=%0d",state);
 $display("R17_FRESH_CENTERED_STOPPED_ARRIVAL_PASS");
 boot;renew=0;repeat(610)step;
 if(active || state!=8 || cmd)$fatal(1,"600ms lease expiry weakened state=%0d",state);
 repeat(5)send_packet(1);
 if(active || cmd)$fatal(1,"lateM restarted expired mission");
 $display("R17_600MS_LEASE_LATE_M_NO_RESTART_PASS");
 $display("SIN12_R17_TWO_STAGE_ALL_PASS");$finish;
end
initial begin #20000000;$fatal(1,"R17 simulation timeout");end
endmodule
