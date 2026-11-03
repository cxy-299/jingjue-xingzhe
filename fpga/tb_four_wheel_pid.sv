`timescale 1ns/1ps

// 四轮闭环到 PWM 的板卡无关联合仿真。
// 用人工测速值代替真实电机，仅检查四路独立性、PID 运算、PWM 占空比和停机行为。
module tb_four_wheel_pid;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg control_tick = 1'b0;
    reg drive_enable = 1'b0;
    integer test_step = 0;
    reg signed [15:0] target [0:3];
    reg signed [15:0] feedback [0:3];
    wire signed [15:0] duty [0:3];
    wire [3:0] pwm;
    wire [3:0] direction;
    integer h0, h1, h2, h3;

    // 仿真专门设 KD=2，确认微分功能可用；实际顶层默认 KD=0，必须实测后调参。
    // PWM 周期缩成 100 个时钟，便于精确统计一个周期内的高电平拍数。
    genvar wheel;
    generate for (wheel = 0; wheel < 4; wheel = wheel + 1) begin: channels
        wheel_pi #(.KP(4), .KI(1), .KD(2), .SHIFT(3)) controller (
            .clk(clk), .rst_n(rst_n), .control_tick_i(control_tick),
            .enable_i(drive_enable), .target_speed_i(target[wheel]),
            .feedback_speed_i(feedback[wheel]), .duty_o(duty[wheel])
        );
        motor_pwm_dir #(.CLK_HZ(1000), .PWM_HZ(10)) carrier (
            .clk(clk), .rst_n(rst_n), .enable_i(drive_enable),
            .duty_i(duty[wheel]), .pwm_o(pwm[wheel]),
            .direction_o(direction[wheel])
        );
    end endgenerate

    always #5 clk = ~clk;

    // 控制 tick 只持续一个时钟；检查点放在下降沿后，避开非阻塞赋值竞争。
    task advance_control;
        begin
            @(negedge clk);
            control_tick = 1'b1;
            @(negedge clk);
            control_tick = 1'b0;
            #1;
        end
    endtask

    // 连续观察完整的 100 拍 PWM 周期，四路计数应互不影响。
    task count_pwm_high;
        integer k;
        begin
            h0 = 0; h1 = 0; h2 = 0; h3 = 0;
            for (k = 0; k < 100; k = k + 1) begin
                @(negedge clk);
                if (pwm[0]) h0 = h0 + 1;
                if (pwm[1]) h1 = h1 + 1;
                if (pwm[2]) h2 = h2 + 1;
                if (pwm[3]) h3 = h3 + 1;
            end
        end
    endtask

    initial begin
        target[0] = 0; target[1] = 0; target[2] = 0; target[3] = 0;
        feedback[0] = 0; feedback[1] = 0; feedback[2] = 0; feedback[3] = 0;
        #12;
        rst_n = 1'b1;

        // 首次使能时 D 项不应把上电前未知的测速变化当作微分冲击。
        test_step = 1;
        target[0] = 200; target[1] = -200; target[2] = 0; target[3] = 100;
        drive_enable = 1'b1;
        advance_control;
        if (duty[0] !== 125 || duty[1] !== -125 ||
            duty[2] !== 0 || duty[3] !== 62)
            $fatal(1, "FAIL step=%0d first PID=%0d,%0d,%0d,%0d",
                   test_step, duty[0], duty[1], duty[2], duty[3]);

        test_step = 2;
        count_pwm_high;
        if (h0 !== 12 || h1 !== 12 || h2 !== 0 || h3 !== 6 ||
            direction !== 4'b0010)
            $fatal(1, "FAIL step=%0d PWM highs=%0d,%0d,%0d,%0d dir=%b",
                   test_step, h0, h1, h2, h3, direction);

        // 反馈变化但没有控制 tick 时，四路占空比均保持原值。
        test_step = 3;
        feedback[0] = 100; feedback[1] = -100; feedback[3] = 50;
        #1;
        if (duty[0] !== 125 || duty[1] !== -125 || duty[3] !== 62)
            $fatal(1, "FAIL step=%0d duty changed without control tick", test_step);

        // D 项对测速上升产生一次反向修正；下一 tick 测速不变时 D 项归零。
        test_step = 4;
        advance_control;
        if (duty[0] !== 62 || duty[1] !== -63 || duty[2] !== 0 || duty[3] !== 31)
            $fatal(1, "FAIL step=%0d derivative=%0d,%0d,%0d,%0d",
                   test_step, duty[0], duty[1], duty[2], duty[3]);
        test_step = 5;
        advance_control;
        if (duty[0] !== 100 || duty[1] !== -100 || duty[3] !== 50)
            $fatal(1, "FAIL step=%0d derivative did not decay", test_step);

        // 只让前左轮进入饱和，积分不能继续累积；其他轮保持独立。
        test_step = 6;
        target[0] = 30000;
        feedback[0] = 0;
        advance_control;
        if (duty[0] !== 1000 || channels[0].controller.integral_acc !== 400)
            $fatal(1, "FAIL step=%0d anti-windup duty=%0d integral=%0d",
                   test_step, duty[0], channels[0].controller.integral_acc);

        // 零速目标清掉旧积分，防止停在视觉死区后残余 PWM 继续驱动。
        test_step = 7;
        target[0] = 0;
        advance_control;
        if (duty[0] !== 0 || channels[0].controller.integral_acc !== 0 ||
            duty[1] === 0)
            $fatal(1, "FAIL step=%0d zero target or lane independence", test_step);

        // 使能关闭应组合关断全部 PWM；下一时钟清除四路 PID 内部状态。
        test_step = 8;
        @(negedge clk);
        drive_enable = 1'b0;
        #1;
        if (pwm !== 4'b0000)
            $fatal(1, "FAIL step=%0d PWM not gated", test_step);
        @(negedge clk);
        #1;
        if (duty[0] !== 0 || duty[1] !== 0 || duty[2] !== 0 || duty[3] !== 0)
            $fatal(1, "FAIL step=%0d PID not cleared", test_step);

        // 重新使能时不能继承停机前的积分或测速微分历史。
        test_step = 9;
        target[0] = 200;
        drive_enable = 1'b1;
        advance_control;
        if (duty[0] !== 125)
            $fatal(1, "FAIL step=%0d restart duty=%0d", test_step, duty[0]);

        $display("PASS tb_four_wheel_pid: four lanes, derivative, anti-windup, stop, PWM");
        $finish;
    end
endmodule
