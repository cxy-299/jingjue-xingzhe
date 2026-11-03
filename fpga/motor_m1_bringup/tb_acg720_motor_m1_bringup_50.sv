`timescale 1ns/1ps
// 缩短时钟时基，验证 50% 占空比、方向 1/0、松手关断及 500 ms 限时。
module tb_acg720_motor_m1_bringup_50;
    reg clk = 0;
    reg s0_n = 1;
    reg s1_n = 1;
    wire pwm, in1, in2;
    wire [3:0] led;
    integer i, highs;
    always #5 clk = ~clk;

    acg720_motor_m1_bringup_50 #(
        .CLK_HZ(1000), .PWM_HZ(10), .STARTUP_MS(5),
        .DEBOUNCE_MS(3), .HOLD_MAX_MS(500)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_pwm_o(pwm), .m1_in1_o(in1), .m1_in2_o(in2), .led_o(led)
    );

    initial begin
        #1;
        if (pwm !== 0 || in1 !== 0 || in2 !== 0)
            $fatal(1, "FAIL: 上电默认输出不为零");
        repeat (9) @(negedge clk);
        if (led[1] !== 1 || led[2] !== 0)
            $fatal(1, "FAIL: 上电等待或电机默认关断异常");

        // 首次按下后 M1 方向固定为 1/0，PWM 一个周期内应有 50 个高电平拍。
        s1_n = 0;
        repeat (6) @(negedge clk);
        if (in1 !== 1 || in2 !== 0 || led[2] !== 1)
            $fatal(1, "FAIL: M1 方向/使能不是 1/0");
        highs = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(negedge clk);
            if (pwm) highs = highs + 1;
        end
        if (highs != 50)
            $fatal(1, "FAIL: PWM 高电平拍数=%0d，应为50", highs);

        s1_n = 1;
        #1;
        if (pwm !== 0 || in1 !== 0 || in2 !== 0 || led[2] !== 0)
            $fatal(1, "FAIL: 松手未立即停车");
        repeat (3) @(negedge clk);

        // 再次按住超过限时应切断，且保持按下时不会自行重新启动。
        s1_n = 0;
        repeat (510) @(negedge clk);
        if (pwm !== 0 || in1 !== 0 || in2 !== 0 || led[3] !== 1)
            $fatal(1, "FAIL: 500 ms 限时停车失效");
        repeat (20) @(negedge clk);
        if (pwm !== 0 || in1 !== 0)
            $fatal(1, "FAIL: 超时后自行重启");
        $display("PASS tb_acg720_motor_m1_bringup_50: 50%% PWM, IN1/IN2=1/0, release, 500ms timeout");
        $finish;
    end
endmodule
