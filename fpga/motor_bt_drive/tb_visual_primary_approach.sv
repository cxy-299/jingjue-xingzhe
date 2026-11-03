`timescale 1ns/1ps
module tb_visual_primary_approach;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,active=0,still=1,sensors=1,hard=0,fault=0,cancel=0,packet=0,match_id=1,geom=1,beam=1,range_sample=0,inv=0;
    reg [31:0] frame=0;reg signed [15:0] bearing=0,yaw=0;
    reg [15:0] coarse=500,uncertainty=200,age=0,distance_mm=500;
    wire [2:0] command,phase;wire [15:0] speed;wire aligned,near_target,arrived,heading_fault;
    visual_primary_approach #(.ARRIVAL_TICKS(3)) dut(
        .clk(clk),.rst_n(rst),.sample_tick_i(1'b1),.active_i(active),.target_ok_i(match_id),
        .wheels_still_i(still),.forward_applied_i(command==1),.inverted_i(inv),.sensors_ok_i(sensors),
        .hard_stop_i(hard),.motor_fault_i(fault),.cancel_i(cancel),.packet_i(packet),
        .matching_i(match_id),.frame_i(frame),.geometry_valid_i(geom),.beam_inside_i(beam),
        .yaw_left_cdeg_i(bearing),.yaw_i(yaw),.coarse_mm_i(coarse),.uncertainty_mm_i(uncertainty),
        .observation_age_ms_i(age),.distance_sample_i(range_sample),.distance_i(distance_mm),.arrival_mm_i(16'd200),
        .command_o(command),.speed_o(speed),.aligned_o(aligned),.near_o(near_target),.arrived_o(arrived),
        .heading_fault_o(heading_fault),.phase_o(phase));
    task ticks(input integer n);repeat(n)begin @(posedge clk);#1;end endtask
    task observe;
        @(negedge clk);frame=frame+1;packet=1;ticks(1);@(negedge clk);packet=0;
    endtask
    task sample_range(input integer mm);
        @(negedge clk);distance_mm=mm;range_sample=1;ticks(1);@(negedge clk);range_sample=0;ticks(1);
    endtask
    task boot;
        @(negedge clk);rst=0;active=0;packet=0;range_sample=0;still=1;sensors=1;hard=0;fault=0;cancel=0;
        match_id=1;geom=1;beam=1;bearing=0;yaw=0;coarse=500;uncertainty=200;age=0;distance_mm=500;inv=0;
        ticks(2);@(negedge clk);rst=1;active=1;observe;ticks(17);observe;ticks(2);
    endtask
    task acquire;
        sample_range(500);sample_range(500);sample_range(500);ticks(2);
    endtask
    integer i;
    initial begin
        boot;
        if(command!=0)$fatal(1,"visual distance alone moved");
        sample_range(4000);sample_range(4000);sample_range(4000);
        if(command!=0 || arrived)$fatal(1,"background ToF accepted");
        acquire;
        if(command!=1 || speed!=8)$fatal(1,"fresh aligned cross-check did not approach phase%0d cmd%0d",phase,command);
        still=0;
        // Every loop is >120ms cumulative, but fresh frames+returns avoid forced rest.
        for(i=0;i<8;i=i+1)begin
            observe;sample_range(500);ticks(3);
            if(command!=1)$fatal(1,"unnecessary step/rest interruption %0d",i);
        end
        sample_range(3000);#1;if(command!=0)$fatal(1,"range jump did not stop");
        boot;acquire;#1;hard=1;#1;if(command!=0)$fatal(1,"hard stop delayed");
        ticks(1);hard=0;ticks(2);if(command!=0)$fatal(1,"hard-stop removal restarted motion");
        boot;acquire;fault=1;#1;if(command!=0)$fatal(1,"motor fault ignored");
        boot;acquire;cancel=1;#1;if(command!=0)$fatal(1,"cancel delayed");
        boot;acquire;match_id=0;#1;if(command!=0)$fatal(1,"identity mismatch ignored");
        boot;acquire;
        // Same frame replay cannot refresh the visual deadline.
        for(i=0;i<32;i=i+1)begin packet=1;sample_range(500);packet=0;end
        if(command!=0)$fatal(1,"replayed image renewed freshness");
        boot;acquire;age=280;observe;if(command!=0)$fatal(1,"old inference accepted");
        boot;beam=0;bearing=250;observe;ticks(18);observe;ticks(2);
        if(command!=5)$fatal(1,"left bearing not bounded yaw phase%0d cmd%0d",phase,command);
        bearing=-250;observe;#1;if(command!=0)$fatal(1,"yaw sign flip did not neutralize");
        ticks(3);if(command!=0)$fatal(1,"yaw reversed without neutral/new frame");
        boot;beam=0;bearing=250;observe;ticks(18);observe;ticks(2);yaw=300;
        #1;if(command!=0)$fatal(1,"IMU target reached but yaw waited for detector");
        boot;inv=1;beam=0;bearing=250;observe;ticks(18);observe;ticks(2);yaw=-300;
        #1;if(command!=0)$fatal(1,"inverted IMU correction did not stop");
        boot;beam=0;bearing=250;yaw=25700;observe;ticks(18);observe;ticks(2);yaw=-25472;
        #1;if(command!=0 || heading_fault)$fatal(1,"wrapped yaw target failed");
        boot;beam=0;bearing=500;observe;ticks(18);observe;ticks(2);
        if(speed!=6)$fatal(1,"large correction speed wrong");yaw=500;
        #1;if(command!=5 || speed!=4)$fatal(1,"IMU remaining-angle taper missing");
        boot;beam=0;bearing=250;observe;ticks(18);observe;ticks(2);yaw=1145;
        #1;if(!heading_fault || command!=0)$fatal(1,"original 8degree budget relaxed");
        boot;acquire;sample_range(420);sample_range(420);sample_range(420);
        if(speed>6)$fatal(1,"near range not slowed");
        sample_range(500);sample_range(500);sample_range(500);
        if(speed>6)$fatal(1,"far rebound increased speed after near range");
        boot;coarse=250;uncertainty=100;observe;sample_range(200);sample_range(200);sample_range(200);ticks(5);
        if(!arrived || command!=0)$fatal(1,"qualified stable arrival failed phase%0d",phase);
        $display("VISUAL_PRIMARY_SAFETY_IMU_AND_APPROACH_CONTRACTS_PASS accelerated10ms epochs, not physical timing or plant");$finish;
    end
    initial begin #100000;$fatal(1,"bench timeout");end
endmodule

