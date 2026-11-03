`timescale 1ns/1ps
// 缩短毫秒对应时钟拍数，只验证按键门控、限时、PWM 和复位。
module tb_acg720_motor_m1_bringup;
    reg clk = 0;
    reg s0_n = 1;
    reg s1_n = 1;
    wire pwm, in1, in2;
    wire [3:0] led;
    integer i, highs;
    always #5 clk = ~clk;

    acg720_motor_m1_bringup #(
        .CLK_HZ(1000), .PWM_HZ(10), .STARTUP_MS(5),
        .DEBOUNCE_MS(3), .HOLD_MAX_MS(120), .DUTY_PERMILLE(100)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_pwm_o(pwm), .m1_in1_o(in1), .m1_in2_o(in2), .led_o(led)
    );

    initial begin
        #1; // 等待寄存器声明初值完成仿真零时刻的 delta 更新。
        if (pwm !== 0 || in1 !== 0 || in2 !== 0)
            $fatal(1, "FAIL: SRAM 初值必须停车");
        repeat (8) @(negedge clk);
        if (led[1] !== 1 || pwm !== 0)
            $fatal(1, "FAIL: 上电就绪/默认停车");

        // S1 的短暂低脉冲不能启动。
        s1_n = 0;
        @(negedge clk);
        s1_n = 1;
        #1;
        if (pwm !== 0 || in1 !== 0)
            $fatal(1, "FAIL: 按键抖动启动");
        repeat (4) @(negedge clk);

        // 连续按住 S1 后，只允许 M1 正转，PWM 在每 100 拍中高 10 拍。
        s1_n = 0;
        repeat (6) @(negedge clk);
        if (in1 !== 1 || in2 !== 0 || led[2] !== 1)
            $fatal(1, "FAIL: M1 正向使能");
        highs = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(negedge clk);
            if (pwm) highs = highs + 1;
        end
        if (highs != 10)
            $fatal(1, "FAIL: PWM 高电平拍数=%0d，应为10", highs);

        // 松手不等待下一时钟，输出立刻为零。
        s1_n = 1;
        #1;
        if (pwm !== 0 || in1 !== 0 || led[2] !== 0)
            $fatal(1, "FAIL: 松手未立即停车");
        repeat (4) @(negedge clk);

        // 再次按住超过 120 拍必须超时，继续按住不得自行重启。
        s1_n = 0;
        repeat (130) @(negedge clk);
        if (pwm !== 0 || in1 !== 0 || led[3] !== 1)
            $fatal(1, "FAIL: 两秒限时停车");
        repeat (20) @(negedge clk);
        if (pwm !== 0 || in1 !== 0)
            $fatal(1, "FAIL: 超时后意外重启");

        // S0 复位必须立即切断电机输出。
        s0_n = 0;
        #1;
        if (pwm !== 0 || in1 !== 0 || in2 !== 0)
            $fatal(1, "FAIL: S0 复位未停车");

        // S1 一直按住时释放 S0，不能因为上电等待结束而自行启动。
        repeat (3) @(negedge clk);
        s0_n = 1;
        repeat (12) @(negedge clk);
        if (pwm !== 0 || in1 !== 0 || led[1] !== 1)
            $fatal(1, "FAIL: S1 上电持续按住时意外启动");
        s1_n = 1;
        repeat (3) @(negedge clk);
        s1_n = 0;
        repeat (6) @(negedge clk);
        if (in1 !== 1 || led[2] !== 1)
            $fatal(1, "FAIL: S1 松开后重新按下仍不能启动");
        s1_n = 1;
        #1;
        if (pwm !== 0 || in1 !== 0)
            $fatal(1, "FAIL: 二次松手未停车");
        $display("PASS tb_acg720_motor_m1_bringup: startup, debounce, 10%% PWM, release, timeout, reset, held-button interlock");
        $finish;
    end
endmodule
