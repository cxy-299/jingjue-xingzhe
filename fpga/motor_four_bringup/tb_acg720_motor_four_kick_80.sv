`timescale 1ns/1ps
// 四路联调自检：引脚独立、错峰起动、80% 保持、按键与复位停车、超时停车。
module tb_acg720_motor_four_kick_80;
    reg clk = 0;
    reg s0_n = 1;
    reg s1_n = 1;
    wire [3:0] pwm, in1, in2;
    wire [5:0] led;
    integer i, j;
    integer highs [0:3];
    always #5 clk = ~clk;

    acg720_motor_four_kick_80 #(
        .CLK_HZ(1000), .PWM_HZ(10), .STARTUP_MS(5),
        .DEBOUNCE_MS(3), .KICK_MS(20),
        .STAGGER_MS(25), .RUN_MAX_MS(250)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led)
    );

    initial begin
        #1;
        if ({pwm,in1,in2} !== 12'b0)
            $fatal(1,"FAIL: 上电未全轮停车");
        repeat (12) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if (in1 !== 4'b0001 || in2 !== 4'b0000 || pwm[0] !== 1'b1)
            $fatal(1,"FAIL: M1 应首先全占空比起动");
        s1_n = 1;
        repeat (7) @(negedge clk);
        if (in1 !== 4'b0001)
            $fatal(1,"FAIL: 过早使能其他电机");
        repeat (19) @(negedge clk);
        if (in1 !== 4'b0011)
            $fatal(1,"FAIL: M2 未按顺序起动，in1=%b",in1);
        repeat (25) @(negedge clk);
        if (in1 !== 4'b0111)
            $fatal(1,"FAIL: M3 未按顺序起动，in1=%b",in1);
        repeat (25) @(negedge clk);
        if (in1 !== 4'b1111 || led[4] !== 1'b1)
            $fatal(1,"FAIL: M4 未起动或 LED6 未亮");
        repeat (25) @(negedge clk);
        for (j=0; j<4; j=j+1) highs[j]=0;
        for (i=0; i<100; i=i+1) begin
            @(negedge clk);
            for (j=0; j<4; j=j+1)
                if (pwm[j]) highs[j]=highs[j]+1;
        end
        for (j=0; j<4; j=j+1)
            if (highs[j] !== 80)
                $fatal(1,"FAIL: M%0d 占空比高电平=%0d，应为 80",j+1,highs[j]);

        // 第二次按下后四路必须一同停机，不留下任一使能端或方向端。
        s1_n = 0;
        repeat (7) @(negedge clk);
        if ({pwm,in1,in2} !== 12'b0 || led[2] !== 1'b0)
            $fatal(1,"FAIL: 第二次按下未全轮停车");
        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        if (in1 !== 4'b0001 || pwm[0] !== 1'b1)
            $fatal(1,"FAIL: 再启动未从 M1 全占空比重来");

        // S0 直接关断全部输出；按住 S1 解除复位不能误启动。
        s0_n = 0;
        #1;
        if ({pwm,in1,in2} !== 12'b0)
            $fatal(1,"FAIL: S0 未立即全轮关断");
        repeat (2) @(negedge clk);
        s0_n = 1;
        repeat (12) @(negedge clk);
        if ({pwm,in1,in2} !== 12'b0)
            $fatal(1,"FAIL: S0 后按住 S1 意外起动");
        s1_n = 1;
        repeat (7) @(negedge clk);
        s1_n = 0;
        repeat (7) @(negedge clk);
        repeat (260) @(negedge clk);
        if ({pwm,in1,in2} !== 12'b0 || led[3] !== 1'b1)
            $fatal(1,"FAIL: 3 秒等效超时后仍有轮子运行");
        $display("PASS tb_acg720_motor_four_kick_80: stagger, four PWM 80%%, toggle, S0, timeout");
        $finish;
    end
endmodule
