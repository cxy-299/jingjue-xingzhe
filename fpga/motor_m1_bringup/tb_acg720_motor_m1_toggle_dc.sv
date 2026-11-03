`timescale 1ns/1ps
// 验证旁路 PWM 后的恒高使能、按键切换、超时和运行中复位。
module tb_acg720_motor_m1_toggle_dc;
    reg clk = 0;
    reg s0_n = 1;
    reg s1_n = 1;
    wire pwm, in1, in2;
    wire [3:0] led;
    always #5 clk = ~clk;

    acg720_motor_m1_toggle_dc #(
        .CLK_HZ(1000), .STARTUP_MS(5), .DEBOUNCE_MS(3), .RUN_MAX_MS(40)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_pwm_o(pwm), .m1_in1_o(in1), .m1_in2_o(in2), .led_o(led)
    );

    initial begin
        #1;
        if ({pwm,in1,in2} !== 3'b000) $fatal(1,"FAIL: 上电未关闭输出");
        repeat (12) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b110 || led[2] !== 1)
            $fatal(1,"FAIL: 启动后应为 PWM/IN1/IN2=1/1/0");
        s1_n = 1;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b110)
            $fatal(1,"FAIL: 松开 S1 后没有持续运行");
        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b000)
            $fatal(1,"FAIL: 第二次按下未停车");

        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b110)
            $fatal(1,"FAIL: 再次启动失败");
        s0_n = 0;
        #1;
        if ({pwm,in1,in2} !== 3'b000)
            $fatal(1,"FAIL: 运行中 S0 未立即切断输出");
        repeat (2) @(negedge clk);
        s0_n = 1;
        repeat (12) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b000)
            $fatal(1,"FAIL: 复位后仍按住 S1 时自动启动");

        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b110)
            $fatal(1,"FAIL: 复位后无法再次启动");
        repeat (45) @(negedge clk);
        if ({pwm,in1,in2} !== 3'b000 || led[3] !== 1)
            $fatal(1,"FAIL: 超时未自动停车");
        $display("PASS tb_acg720_motor_m1_toggle_dc: DC enable, toggle, reset, timeout");
        $finish;
    end
endmodule
