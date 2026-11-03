`timescale 1ns/1ps
module tb_sin12_r7_guard;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,sample_tick_i=0,request_i=0,inverted_i=0,cancel_i=0;
    reg [15:0] sequence_i=0;
    reg signed [15:0] angle_cdeg_i=9000,yaw_i=3984;
    reg ascii_valid_i=0;reg [7:0] ascii_i=0;
    wire active_o,fault_o;wire [3:0] state_o;wire [15:0] sequence_o,target_speed_o;
    wire signed [15:0] target_yaw_o,error_o;wire [2:0] command_o;
    imu_turn_guard #(.CLK_HZ(1000),.NEUTRAL_MS(5),.SETTLE_TICKS(3),.PIPELINED_TARGET(1)) dut(
        .clk(clk),.rst_n(rst_n),.sample_tick_i(sample_tick_i),.request_i(request_i),
        .sequence_i(sequence_i),.angle_cdeg_i(angle_cdeg_i),.speed_i(8'd12),.inverted_i(inverted_i),
        .yaw_i(yaw_i),.sensors_ok_i(1'b1),.hard_stop_i(1'b0),.motor_fault_i(1'b0),
        .other_active_i(1'b0),.cancel_i(cancel_i),.ascii_valid_i(ascii_valid_i),.error_i(1'b0),
        .ascii_i(ascii_i),.active_o(active_o),.fault_o(fault_o),.state_o(state_o),
        .sequence_o(sequence_o),.target_yaw_o(target_yaw_o),.error_o(error_o),
        .command_o(command_o),.target_speed_o(target_speed_o));
    task arm;
        @(negedge clk);ascii_valid_i=1;ascii_i="S";
        @(negedge clk);ascii_valid_i=0;repeat(7)@(negedge clk);
    endtask
    task request;
        sequence_i=sequence_i+1;request_i=1;
        @(negedge clk);request_i=0;
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;arm();request();
        // Change every request field immediately; accepted yaw/angle stay atomic.
        yaw_i=0;angle_cdeg_i=-9000;inverted_i=1;
        repeat(4)begin @(negedge clk);if(command_o!=0)$fatal(1,"old target drove wheels while pending");end
        repeat(8)@(negedge clk);
        if(target_yaw_o!=16851 || sequence_o!=1 || command_o!=5)$fatal(1,"accepted left90 target/direction");
        // Requesting another turn while busy cannot change target or sequence.
        request();repeat(8)@(negedge clk);
        if(target_yaw_o!=16851 || sequence_o!=1)$fatal(1,"busy request replaced active target");
        yaw_i=16851;sample_tick_i=1;repeat(4)@(negedge clk);sample_tick_i=0;
        if(active_o || state_o!=3 || command_o!=0)$fatal(1,"at angle did not complete/stop");
        // Abort during arithmetic latency, then renew: no deferred start.
        arm();yaw_i=21140;angle_cdeg_i=9000;inverted_i=0;request();
        cancel_i=1;@(negedge clk);cancel_i=0;
        repeat(12)begin @(negedge clk);if(active_o || command_o!=0)$fatal(1,"cancelled pending turn restarted");end
        ascii_valid_i=1;ascii_i="G";@(negedge clk);ascii_valid_i=0;
        repeat(8)@(negedge clk);if(active_o)$fatal(1,"G restarted canceled turn");
        arm();request();repeat(12)@(negedge clk);
        if(target_yaw_o!=-17465 || command_o!=5)$fatal(1,"147.856+90 wrap target");
        $display("R7_TARGET_ATOMIC_PENDING_CANCEL_BUSY_DONE_PASS");$finish;
    end
    initial begin #20000;$fatal(1,"timeout");end
endmodule
