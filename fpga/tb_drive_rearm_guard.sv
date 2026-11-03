`timescale 1ns/1ps

// 故障解除边界：PWM 允许信号不得在下一个控制周期到来之前自行恢复。
module tb_drive_rearm_guard;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg control_tick = 1'b0;
    reg fault = 1'b0;
    wire allow;
    always #5 clk = ~clk;

    drive_rearm_guard dut (
        .clk(clk), .rst_n(rst_n), .control_tick_i(control_tick),
        .fault_i(fault), .allow_o(allow)
    );

    task automatic tick;
        begin
            @(negedge clk);
            control_tick = 1'b1;
            @(negedge clk);
            control_tick = 1'b0;
            #1;
        end
    endtask

    initial begin
        #2;
        if (allow !== 1'b0) $fatal(1, "FAIL reset not safe");
        @(negedge clk);
        rst_n = 1'b1;
        #1;
        if (allow !== 1'b0) $fatal(1, "FAIL startup before tick");
        tick;
        if (allow !== 1'b1) $fatal(1, "FAIL startup rearm");

        // 故障应组合立即关断，不等时钟或控制周期。
        #2 fault = 1'b1;
        #1;
        if (allow !== 1'b0) $fatal(1, "FAIL fault immediate stop");
        @(posedge clk);
        #1 fault = 1'b0;
        #1;
        if (allow !== 1'b0) $fatal(1, "FAIL early restart");
        tick;
        if (allow !== 1'b1) $fatal(1, "FAIL normal rearm");

        // 若故障在控制 tick 期间仍存在，不能放行。
        fault = 1'b1;
        tick;
        if (allow !== 1'b0) $fatal(1, "FAIL tick while fault");
        fault = 1'b0;
        #1;
        if (allow !== 1'b0) $fatal(1, "FAIL restart after fault tick");
        tick;
        if (allow !== 1'b1) $fatal(1, "FAIL second rearm");

        // 子时钟故障脉冲仍须被锁存，不能在故障刚消失时重放旧 PWM。
        #1 fault = 1'b1;
        #1;
        if (allow !== 1'b0) $fatal(1, "FAIL short fault immediate stop");
        fault = 1'b0;
        #1;
        if (allow !== 1'b0) $fatal(1, "FAIL short fault not latched");
        tick;
        if (allow !== 1'b1) $fatal(1, "FAIL short fault rearm");

        $display("PASS tb_drive_rearm_guard: immediate stop, delayed rearm, short pulse latch");
        $finish;
    end
endmodule
