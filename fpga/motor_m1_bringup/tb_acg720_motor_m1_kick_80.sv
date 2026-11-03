`timescale 1ns/1ps
// 用缩短的时基检查全占空比起动、80% 保持、按键停车、S0 停车和运行超时。
module tb_acg720_motor_m1_kick_80;
    reg clk = 0;
    reg s0_n = 1;
    reg s1_n = 1;
    wire pwm, in1, in2;
    wire [3:0] led;
    integer i, highs;
    always #5 clk = ~clk;

    acg720_motor_m1_kick_80 #(
        .CLK_HZ(1000), .PWM_HZ(10), .STARTUP_MS(5),
        .DEBOUNCE_MS(3), .KICK_MS(20), .RUN_MAX_MS(250)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_pwm_o(pwm), .m1_in1_o(in1), .m1_in2_o(in2), .led_o(led)
    );

    initial begin
        #1;
        if ({pwm,in1,in2} !== 3'b000)
            $fatal(1,"FAIL: 上电未停车");
        repeat (12) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b110 || led[2] !== 1)
            $fatal(1,"FAIL: 首次按下未进入全占空比起动");
        s1_n = 1;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b110)
            $fatal(1,"FAIL: 起动阶段提前退出或松键后停车");
        repeat (20) @(negedge clk);
        highs = 0;
        for (i=0; i<100; i=i+1) begin
            @(negedge clk);
            if (pwm) highs = highs + 1;
        end
        if (highs !== 80 || in1 !== 1 || in2 !== 0)
            $fatal(1,"FAIL: 保持阶段高电平拍数=%0d，应为 80",highs);

        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b000)
            $fatal(1,"FAIL: 第二次按下未停车");
        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b110)
            $fatal(1,"FAIL: 再次启动未重置全占空比起动窗口");

        // 在运行中复位时，输出必须异步立即回到低电平。
        s0_n = 0;
        #1;
        if ({pwm,in1,in2} !== 3'b000)
            $fatal(1,"FAIL: S0 未立即停车");
        repeat (2) @(negedge clk);
        s0_n = 1;
        repeat (12) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b000)
            $fatal(1,"FAIL: S0 后按住 S1 自动启动");
        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        repeat (260) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b000 || led[3] !== 1)
            $fatal(1,"FAIL: 超时后仍在输出");
        $display("PASS tb_acg720_motor_m1_kick_80: kick, 80%% PWM, toggle, S0, timeout");
        $finish;
    end
endmodule
