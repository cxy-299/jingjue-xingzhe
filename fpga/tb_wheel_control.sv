`timescale 1ns/1ps

// 四轮底层单元测试：运动学、正交编码器、速度 PI、PWM/方向。
// 只检查数学与时序行为，不表示 TB6612 引脚已经接好或电机可以上电。
module tb_wheel_control;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    integer test_step = 0;

    reg signed [15:0] vx = 0, vy = 0, omega = 0;
    wire signed [15:0] fl, fr, rl, rr;
    mecanum_kinematics mixer (
        .vx_i(vx), .vy_i(vy), .omega_i(omega),
        .wheel_fl_o(fl), .wheel_fr_o(fr),
        .wheel_rl_o(rl), .wheel_rr_o(rr)
    );

    reg encoder_a = 0, encoder_b = 0, sample_tick = 0;
    wire signed [31:0] position;
    wire signed [15:0] speed;
    encoder_speed encoder (
        .clk(clk), .rst_n(rst_n), .encoder_a_i(encoder_a),
        .encoder_b_i(encoder_b), .sample_tick_i(sample_tick),
        .position_o(position), .speed_o(speed)
    );

    reg pi_tick = 0, pi_enable = 0;
    reg signed [15:0] pi_target = 0, pi_feedback = 0;
    wire signed [15:0] pi_duty;
    wheel_pi controller (
        .clk(clk), .rst_n(rst_n), .control_tick_i(pi_tick),
        .enable_i(pi_enable), .target_speed_i(pi_target),
        .feedback_speed_i(pi_feedback), .duty_o(pi_duty)
    );

    // 缩小 PWM 周期为 100 个时钟，只为快速仿真占空比。
    reg pwm_enable = 0;
    reg signed [15:0] pwm_duty = 0;
    wire pwm, direction;
    motor_pwm_dir #(.CLK_HZ(1000), .PWM_HZ(10)) pwm_driver (
        .clk(clk), .rst_n(rst_n), .enable_i(pwm_enable),
        .duty_i(pwm_duty), .pwm_o(pwm), .direction_o(direction)
    );

    always #5 clk = ~clk;

    task check_wheels;
        input signed [15:0] efl, efr, erl, err;
        begin
            #1;
            if (fl !== efl || fr !== efr || rl !== erl || rr !== err) begin
                $display("FAIL step=%0d wheels=%0d,%0d,%0d,%0d", test_step, fl, fr, rl, rr);
                $finish;
            end
        end
    endtask

    // 每个 A/B 状态保持四个时钟，给两级输入同步器和计数器留足时间。
    task encoder_state;
        input a, b;
        begin
            @(negedge clk);
            encoder_a = a;
            encoder_b = b;
            repeat (4) @(negedge clk);
        end
    endtask

    task sample_encoder;
        begin
            @(negedge clk);
            sample_tick = 1'b1;
            @(negedge clk);
            sample_tick = 1'b0;
            #1;
        end
    endtask

    task update_pi;
        begin
            @(negedge clk);
            pi_tick = 1'b1;
            @(negedge clk);
            pi_tick = 1'b0;
            #1;
        end
    endtask

    task count_pwm_high;
        output integer high_count;
        integer k;
        begin
            high_count = 0;
            for (k = 0; k < 100; k = k + 1) begin
                @(negedge clk);
                if (pwm === 1'b1)
                    high_count = high_count + 1;
            end
        end
    endtask

    integer highs;
    initial begin
        #12;
        rst_n = 1'b1;

        // 1. 前进：四轮同向；正 vy 为右移；正 omega 为逆时针。
        test_step = 1;
        vx = 300; vy = 0; omega = 0;
        check_wheels(300, 300, 300, 300);
        test_step = 2;
        vx = 0; vy = 200;
        check_wheels(-200, 200, 200, -200);
        test_step = 3;
        vy = 0; omega = 200;
        check_wheels(-200, 200, -200, 200);
        test_step = 4;
        vx = 1000; vy = 1000; omega = 0;
        check_wheels(0, 1000, 1000, 0); // 超出幅度时四轮等比例缩放。

        // 5. 编码器一个完整正交循环是 +4 计数，反向循环是 -4。
        test_step = 5;
        encoder_state(0, 1); encoder_state(1, 1);
        encoder_state(1, 0); encoder_state(0, 0);
        sample_encoder;
        if (position !== 4 || speed !== 4) begin
            $display("FAIL step=%0d encoder forward position=%0d speed=%0d", test_step, position, speed);
            $finish;
        end
        test_step = 6;
        encoder_state(1, 0); encoder_state(1, 1);
        encoder_state(0, 1); encoder_state(0, 0);
        sample_encoder;
        if (position !== 0 || speed !== -4) begin
            $display("FAIL step=%0d encoder reverse position=%0d speed=%0d", test_step, position, speed);
            $finish;
        end

        // 7. 默认 PI: (4*误差 + 积分) / 8，控制周期之间保持输出。
        test_step = 7;
        pi_enable = 1;
        pi_target = 200;
        pi_feedback = 0;
        update_pi;
        if (pi_duty !== 125) begin
            $display("FAIL step=%0d PI first duty=%0d", test_step, pi_duty);
            $finish;
        end
        test_step = 8;
        pi_feedback = 100;
        #1;
        if (pi_duty !== 125) begin
            $display("FAIL step=%0d PI changed without tick", test_step);
            $finish;
        end
        update_pi;
        if (pi_duty !== 87) begin
            $display("FAIL step=%0d PI second duty=%0d", test_step, pi_duty);
            $finish;
        end

        // 9. 禁用后下一时钟必须清零，不用等下一次控制 tick。
        test_step = 9;
        @(negedge clk);
        pi_enable = 0;
        @(negedge clk);
        #1;
        if (pi_duty !== 0 || controller.integral_acc !== 0) begin
            $display("FAIL step=%0d PI disable duty=%0d integral=%0d",
                     test_step, pi_duty, controller.integral_acc);
            $finish;
        end
        test_step = 10;
        pi_enable = 1;
        pi_feedback = 0;
        update_pi;
        if (pi_duty !== 125) begin
            $display("FAIL step=%0d PI restart retained old integral", test_step);
            $finish;
        end

        // 11. 50% PWM 必须在 100 拍中高 50 拍；负号只改变方向。
        test_step = 11;
        pwm_enable = 1;
        pwm_duty = 500;
        count_pwm_high(highs);
        if (highs !== 50 || direction !== 0) begin
            $display("FAIL step=%0d PWM positive highs=%0d dir=%b", test_step, highs, direction);
            $finish;
        end
        test_step = 12;
        pwm_duty = -500;
        count_pwm_high(highs);
        if (highs !== 50 || direction !== 1) begin
            $display("FAIL step=%0d PWM negative highs=%0d dir=%b", test_step, highs, direction);
            $finish;
        end
        test_step = 13;
        pwm_enable = 0;
        #1;
        if (pwm !== 0) begin
            $display("FAIL step=%0d PWM did not stop immediately", test_step);
            $finish;
        end

        $display("PASS tb_wheel_control: mixer, encoder, PI disable, PWM");
        $finish;
    end
endmodule
