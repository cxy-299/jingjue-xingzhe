`timescale 1ns/1ps
// 用压缩时基验证上电按住不自启、两次按键启停、50% PWM 和限时停车。
module tb_acg720_motor_m1_toggle_50;
    reg clk = 0;
    reg s0_n = 1;
    reg s1_n = 0;
    wire pwm, in1, in2;
    wire [3:0] led;
    integer i, highs;
    always #5 clk = ~clk;

    acg720_motor_m1_toggle_50 #(
        .CLK_HZ(1000), .PWM_HZ(10), .STARTUP_MS(5),
        .DEBOUNCE_MS(3), .RUN_MAX_MS(300)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_pwm_o(pwm), .m1_in1_o(in1), .m1_in2_o(in2), .led_o(led)
    );

    initial begin
        #1;
        if (pwm !== 0 || in1 !== 0 || in2 !== 0)
            $fatal(1, "FAIL: 上电默认未停车");
        repeat (12) @(negedge clk);
        if (led[1] !== 1 || led[2] !== 0)
            $fatal(1, "FAIL: 上电持续按住 S1 时自行启动");

        // 先松开再按下，才允许第一次启动。
        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if (led[2] !== 1 || in1 !== 1 || in2 !== 0)
            $fatal(1, "FAIL: 第一次按下未启动或方向不是 1/0");
        s1_n = 1;
        repeat (7) @(negedge clk);
        if (led[2] !== 1)
            $fatal(1, "FAIL: 松开 S1 后没有继续运行");

        highs = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(negedge clk);
            if (pwm) highs = highs + 1;
        end
        if (highs != 50)
            $fatal(1, "FAIL: 50%% PWM 高电平拍数=%0d", highs);

        // 第二次按下切换到停机，且没有自动重新启动。
        s1_n = 0;
        repeat (7) @(negedge clk);
        if (led[2] !== 0 || pwm !== 0 || in1 !== 0)
            $fatal(1, "FAIL: 第二次按下未停车");
        repeat (10) @(negedge clk);
        if (led[2] !== 0)
            $fatal(1, "FAIL: 按键保持按下时重复切换");

        // 第三次启动后在运行中按 S0，不能等到下一个时钟才切断输出。
        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if (led[2] !== 1)
            $fatal(1, "FAIL: 第三次按下未启动");
        s0_n = 0;
        #1;
        if (pwm !== 0 || in1 !== 0 || in2 !== 0 || led[2] !== 0)
            $fatal(1, "FAIL: 运行中按 S0 未立即停车");
        repeat (2) @(negedge clk);
        s0_n = 1;
        repeat (12) @(negedge clk);
        if (led[2] !== 0)
            $fatal(1, "FAIL: S0 复位后按住 S1 自行启动");

        // 复位后先松开 S1，再按下启动；超过设定上限必须自动停机。
        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if (led[2] !== 1)
            $fatal(1, "FAIL: S0 复位后无法再次启动");
        repeat (310) @(negedge clk);
        if (led[2] !== 0 || led[3] !== 1 || pwm !== 0)
            $fatal(1, "FAIL: 超时未自动停车");
        $display("PASS tb_acg720_motor_m1_toggle_50: toggled run/stop, 50%% PWM, 1/0, timeout, reset");
        $finish;
    end
endmodule
