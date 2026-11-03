`timescale 1ns/1ps
module tb_sin12_r10_mission_align;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,pkt=0,av=0,hard=0,ok=1,cancel=0,still=1;
reg selected=1,visible=1,confirmed=1,feed=1,renew=1;
reg[7:0]ab=0;reg[15:0]seq=0;reg[31:0]job=1,packetjob=1,lockid=42;
reg signed[15:0]center=-5000,yaw=0;reg[15:0]distance=900;
wire active;wire[31:0]id,locked;wire[15:0]cls,speed;wire[3:0]state;wire[2:0]leg,cmd;
vision_mission_guard #(.CLK_HZ(1000),.CONTROLLED_ALIGN(1),.ARRIVAL_TICKS(3)) dut(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.request_id_i(job),.request_class_i(16'd39),.request_distance_i(16'd300),
.request_red_i(1'b0),.request_inverted_i(1'b0),.packet_i(pkt),.packet_sequence_i(seq),.packet_mission_i(packetjob),
.packet_lock_i(lockid),.packet_class_i(16'd39),.packet_red_i(1'b0),.selected_i(selected),.visible_i(visible),.confirmed_i(confirmed),
.center_i(center),.yaw_i(yaw),.distance_i(distance),.distance_sample_i(1'b0),.sensors_ok_i(ok),.hard_stop_i(hard),.motor_fault_i(1'b0),
.other_active_i(1'b0),.cancel_i(cancel),.wheels_still_i(still),.ascii_valid_i(av),.error_i(1'b0),.ascii_i(ab),
.active_o(active),.id_o(id),.lock_o(locked),.class_o(cls),.state_o(state),.leg_o(leg),.command_o(cmd),.speed_o(speed));
integer clockcount=0,n,runlength,restlength,bursts,maxrun,previous,motion;
task step;begin
 @(negedge clk);clockcount=clockcount+1;tick=(clockcount%10==0);pkt=feed && clockcount%20==0;
 if(pkt)seq=seq+1;
 av=renew && clockcount%50==0;ab="M";
 @(posedge clk);#1;tick=0;pkt=0;av=0;
end endtask
task boot(input integer number);begin
 rst=0;repeat(4)@(negedge clk);rst=1;job=number;packetjob=number;lockid=42;center=-5000;yaw=0;distance=900;
 selected=1;visible=1;confirmed=1;feed=1;renew=1;still=1;hard=0;ok=1;cancel=0;clockcount=0;
 @(negedge clk);av=1;ab="S";@(negedge clk);av=0;repeat(180)step;
 @(negedge clk);req=1;@(negedge clk);req=0;repeat(5)step;
 if(!active)$fatal(1,"New mission did not start %d state=%d",number,state);
end endtask
task wait_move;begin
 n=0;while(active && cmd==0 && n<1000)begin step;n=n+1;end
 if(cmd!=3 && cmd!=4)$fatal(1,"No alignment move state=%d cmd=%d",state,cmd);
end endtask
initial begin
 boot(1);runlength=0;restlength=1000;bursts=0;maxrun=0;previous=0;
 repeat(1500)begin
  step;
  if(cmd==3)begin
   if(speed!=6)$fatal(1,"Alignment speed not bounded");
   if(!previous)begin
    if(bursts && restlength<300)$fatal(1,"No coast/observe interval %d",restlength);
    bursts=bursts+1;restlength=0;
   end
   runlength=runlength+1;if(runlength>maxrun)maxrun=runlength;
   if(runlength>120)$fatal(1,"Unbounded blind lateral drive");
  end else begin if(cmd!=0)$fatal(1,"Unexpected direction");runlength=0;restlength=restlength+1;end
  previous=cmd;
 end
 if(bursts<2||maxrun<100)$fatal(1,"Far alignment did not move and reobserve");
 $display("R10_ALIGN_120MS_DRIVE_300MS_REOBSERVE_PASS bursts=%d maxrun=%d",bursts,maxrun);
 // Near centre gets a shorter pulse, not lower-than-supported wheel references.
 boot(2);center=2000;wait_move;runlength=0;
 while(active && cmd!=0 && runlength<100)begin step;runlength=runlength+1;end
 if(runlength>60 || runlength<40)$fatal(1,"Near alignment pulse duration %d",runlength);
 // No new observation after a coast = no new motion, even if wheels stop.
 feed=0;still=0;repeat(330)step;still=1;repeat(100)step;
 if(cmd || !active)$fatal(1,"Coast packet authorized delayed movement");
 feed=1;wait_move;
 // Same class with a different lock must stop, not silently switch object.
 lockid=43;repeat(25)step;if(active || cmd || state!=14)$fatal(1,"Identity replacement resumed");
 $display("R10_NEAR60_FRESH_AFTER_STILL_IDENTITY_PASS");
 boot(3);wait_move;visible=0;repeat(25)step;
 if(active||cmd||state!=14)$fatal(1,"Target loss did not stop");
 visible=1;repeat(100)step;if(active||cmd)$fatal(1,"Target return auto restarted");
 boot(4);wait_move;yaw=1200;step;
 if(active||cmd||state!=15)$fatal(1,"Excessive lateral yaw not stopped state=%d",state);
 yaw=0;repeat(100)step;if(active||cmd)$fatal(1,"Heading return auto restarted");
 $display("R10_TARGET_LOST_AND_8DEG_HEADING_LIMIT_STOP_PASS");
 boot(5);wait_move;hard=1;#1;if(cmd||speed)$fatal(1,"Hard-stop physical gate delayed");step;hard=0;
 if(active||cmd||state!=10)$fatal(1,"Hard-stop not latched");
 boot(6);wait_move;ok=0;#1;if(cmd)$fatal(1,"Invalid sensor gate delayed");step;ok=1;
 if(active||cmd||state!=10)$fatal(1,"Invalid sensor restarted");
 boot(7);wait_move;cancel=1;#1;if(cmd)$fatal(1,"Cancel gate delayed");step;cancel=0;
 if(active||cmd||state!=12)$fatal(1,"Cancel not latched");
 boot(8);wait_move;renew=0;repeat(320)step;
 if(active||cmd||state!=8)$fatal(1,"Lease timeout not latched");renew=1;repeat(100)step;if(active||cmd)$fatal(1,"Lease renewal restarted");
 $display("R10_ALIGN_IMMEDIATE_HARD_SENSOR_CANCEL_LEASE_PASS");
 boot(9);wait_move;center=0;repeat(180)step;
 if(state!=4 || cmd!=1)$fatal(1,"Centred target did not approach state=%d cmd=%d",state,cmd);
 distance=310;#1;if(cmd||speed)$fatal(1,"Arrival range failed immediate stop");
 repeat(100)step;if(active||state!=6||cmd)$fatal(1,"Arrival did not complete");
 $display("R10_CONTROLLED_ALIGNMENT_APPROACH_ARRIVAL_PASS");$finish;
end
initial begin #3000000;$fatal(1,"Alignment test timeout");end
endmodule
