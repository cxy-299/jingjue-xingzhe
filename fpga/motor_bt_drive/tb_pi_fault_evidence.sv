`timescale 1ns/1ps
// Protection edge cases. This is not a motor/traction model.
module tb_pi_fault_evidence;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=0,tick=0;
    reg signed [16:0] actual=0;
    reg signed [15:0] target=0;
    wire signed [15:0] duty,trip_speed;
    wire fault,feedback;wire [2:0] reason;wire [15:0] trip_duty;
    motor_four_pi_channel #(.KICK_CYCLES(20),.LOSS_TICKS(70)) dut(
        .clk(clk),.rst_n(rst),.enable_i(en),.sample_tick_i(tick),
        .forward_speed_i(actual),.target_counts_i(target),.duty_o(duty),
        .fault_o(fault),.feedback_seen_o(feedback),.fault_reason_o(reason),
        .fault_speed_o(trip_speed),.fault_duty_o(trip_duty));
    task sample(input integer speed);
        begin @(negedge clk);actual=speed;tick=1;@(negedge clk);tick=0;repeat(4)@(negedge clk);end
    endtask
    task reset;
        begin en=0;rst=0;target=0;actual=0;repeat(3)@(negedge clk);rst=1;end
    endtask
    task start;
        begin target=8;en=1;repeat(25)@(negedge clk);end
    endtask
    integer k;reg [15:0] saved_duty;
    initial begin
        reset();en=1;
        repeat(80)begin sample(0);if(duty!==0 || fault)$fatal(1,"zero target must never kick or accumulate loss");end
        start();
        for(k=0;k<69;k=k+1)begin sample(0);if(fault)$fatal(1,"loss tripped before 70 ticks");end
        saved_duty=duty;sample(0);
        if(!fault || reason!=1 || trip_speed!=0 || trip_duty!=saved_duty || duty!=0)
            $fatal(1,"loss evidence/counter rollover protection failed");
        en=0;target=0;repeat(10)@(negedge clk);
        if(!fault || reason!=1 || trip_duty!=saved_duty)$fatal(1,"first fault evidence lost after stop");
        reset();start();sample(-3);sample(-3);
        if(fault)$fatal(1,"reverse fault too early");
        sample(-3);if(!fault || reason!=2 || trip_speed!=-3)$fatal(1,"reverse cause mismatch");
        reset();start();sample(51);
        if(!fault || reason!=4 || trip_speed!=51)$fatal(1,"overspeed cause mismatch");
        reset();start();
        repeat(90)begin sample(8);if(fault)$fatal(1,"healthy feedback false trip");end
        @(negedge clk);target=0;#1;
        if(duty!==0)$fatal(1,"zero reference did not gate duty immediately");
        repeat(80)sample(0);
        if(fault)$fatal(1,"zero reference accumulated no-feedback fault");
        $display("PI_ZERO_REFERENCE_LONG_COUNTER_FIRST_FAULT_EVIDENCE_PASS");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
