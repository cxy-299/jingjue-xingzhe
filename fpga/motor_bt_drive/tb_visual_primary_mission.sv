`timescale 1ns/1ps
// CLK_HZ=1000 and one10ms sample per10cycles: functional scaled-clock test,
// not production50MHz timing, plant, or routed/SDF acceptance.
module tb_visual_primary_mission;
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,req=0,pkt=0,av=0,hard=0,still=1,ds=0,renew=1,feed=1;
reg [7:0] ascii=0;reg [15:0] seq=0;reg [31:0] frame=0;
reg signed[15:0] bearing=0,yaw=0;reg beam=1;reg [15:0] range_mm=500,coarse=500,uncertainty=200;
wire active;wire [2:0] cmd;wire [15:0] speed;wire [3:0] state;
vision_mission_guard #(.CLK_HZ(1000),.CONTROLLED_ALIGN(1),.MISSION_REFINEMENT(1),.VISUAL_PRIMARY(1),.ARRIVAL_TICKS(5)) dut(
.clk(clk),.rst_n(rst),.sample_tick_i(tick),.request_i(req),.request_id_i(32'd1),.request_class_i(16'd39),.request_distance_i(16'd200),
.request_red_i(1'b0),.request_inverted_i(1'b0),.packet_i(pkt),.packet_sequence_i(seq),.packet_mission_i(32'd1),
.packet_lock_i(32'd2),.packet_class_i(16'd39),.packet_red_i(1'b0),.selected_i(1'b1),.visible_i(1'b1),.confirmed_i(1'b1),
.center_i(16'sd0),.yaw_i(yaw),.distance_i(range_mm),.distance_sample_i(ds),.sensors_ok_i(1'b1),.hard_stop_i(hard),.motor_fault_i(1'b0),
.other_active_i(1'b0),.cancel_i(1'b0),.wheels_still_i(still),.ascii_valid_i(av),.error_i(1'b0),.ascii_i(ascii),
.geometry_frame_i(frame),.geometry_valid_i(1'b1),.geometry_beam_i(beam),.geometry_yaw_i(bearing),
.geometry_range_i(coarse),.geometry_uncertainty_i(uncertainty),.geometry_age_i(16'd0),
.active_o(active),.state_o(state),.command_o(cmd),.speed_o(speed),.id_o(),.lock_o(),.class_o(),.leg_o());
integer cycle=0,i,run_length=0;
task step;begin
 @(negedge clk);cycle=cycle+1;tick=cycle%10==0;pkt=feed && cycle%20==0;ds=cycle%20==0;
 if(pkt)begin seq=seq+1;frame=frame+1;end
 av=renew && cycle%50==0;ascii="M";
 @(posedge clk);#1;tick=0;pkt=0;av=0;ds=0;
 if($isunknown({active,state,cmd,speed}))$fatal(1,"unknown smart-mission outputs");
end endtask
task start;begin
 @(negedge clk);rst=0;hard=0;feed=1;renew=1;still=1;range_mm=500;coarse=500;uncertainty=200;bearing=0;beam=1;yaw=0;
 repeat(3)@(negedge clk);rst=1;
 @(negedge clk);av=1;ascii="S";@(negedge clk);av=0;
 repeat(180)step;@(negedge clk);req=1;@(negedge clk);req=0;
 for(i=0;i<1000 && cmd!=1;i=i+1)step;
 if(!active || cmd!=1)$fatal(1,"smart mission did not start state%0d",state);
end endtask
initial begin
 start;
 still=0;
 repeat(500)begin step;if(cmd==1)run_length=run_length+1;else run_length=0;end
 if(run_length<400)$fatal(1,"parent still enforces original120ms steps %0d",run_length);
 // Existing visual timeout and300ms lease remain board-owned; no host reset.
 renew=0;repeat(305)step;
 if(active || state!=8 || cmd!=0)$fatal(1,"300ms lease relaxed state%0d",state);
 start;hard=1;#1;if(cmd!=0)$fatal(1,"parent live hard stop delayed");
 step;if(active || state!=10)$fatal(1,"parent hard stop not terminal");
 start;coarse=250;uncertainty=100;range_mm=200;still=1;
 repeat(250)step;if(active || state!=6 || cmd!=0)$fatal(1,"stable mission completion failed state%0d",state);
 start;feed=0;repeat(310)step;if(cmd!=0)$fatal(1,"300ms image stale did not stop");
 repeat(1000)step;if(active || state!=9)$fatal(1,"1200ms visual timeout changed state%0d",state);
 $display("VISUAL_PRIMARY_PARENT_CONTINUOUS_LEASE_HARDSTOP_ARRIVAL_TIMEOUT_PASS");$finish;
end
initial begin #200000;$fatal(1,"parent timeout");end
endmodule

