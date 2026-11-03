`timescale 1ns/1ps
module tb_acg720_motor_encoder_direction;
    reg clk = 1'b0;
    reg s0_n = 1'b0;
    reg s1_n = 1'b1;
    reg enc_a = 1'b0;
    reg enc_b = 1'b0;
    wire [3:0] pwm;
    wire [3:0] in1;
    wire [3:0] in2;
    wire [5:0] led;
    integer k;

    always #5 clk = ~clk;

    // 缩短时钟参数，使实际 700 ms 的硬超时能在微秒级仿真时间内覆盖。
    acg720_motor_encoder_direction #(
        .CLK_HZ(1000), .PWM_HZ(100), .STARTUP_MS(2),
        .DEBOUNCE_MS(2), .KICK_MS(10), .RUN_MAX_MS(70)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_encoder_a_i(enc_a), .m1_encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2), .led_o(led)
    );

    task check_safe_outputs;
        begin
            if (pwm[3:1] !== 3'b000 || in1[3:1] !== 3'b000 || in2 !== 4'b0000) begin
                $display("FAIL: inactive motors must stay low");
                $finish;
            end
        end
    endtask

    task negative_quadrature_cycle;
        begin
            // 00→10→11→01→00 对现有解码器而言是负方向。
            enc_a = 1'b1; repeat (4) @(posedge clk);
            enc_b = 1'b1; repeat (4) @(posedge clk);
            enc_a = 1'b0; repeat (4) @(posedge clk);
            enc_b = 1'b0; repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        s0_n = 1'b1;
        repeat (10) @(posedge clk);
        if (led[1] !== 1'b1 || in1 !== 4'b0000) begin
            $display("FAIL: startup must be ready and stopped");
            $finish;
        end
        check_safe_outputs();

        // S1 经消抖后启动；只允许 M1 的 PWM/IN1 活动。
        s1_n = 1'b0;
        repeat (7) @(posedge clk);
        s1_n = 1'b1;
        repeat (8) @(posedge clk);
        if (in1 !== 4'b0001 || led[2] !== 1'b1) begin
            $display("FAIL: M1 did not start");
            $finish;
        end
        check_safe_outputs();

        negative_quadrature_cycle();
        if (led[4] !== 1'b1 || led[5] !== 1'b1) begin
            $display("FAIL: M1 negative encoder direction not latched");
            $finish;
        end

        // 超时必须使电机和其余三路全部关闭，但保留脉冲与方向记录供人观察。
        repeat (90) @(posedge clk);
        if (pwm !== 4'b0000 || in1 !== 4'b0000 || led[3] !== 1'b1 || led[4] !== 1'b1) begin
            $display("FAIL: hard timeout did not stop motor or preserve result");
            $finish;
        end
        check_safe_outputs();

        // S0 复位要立即清除电机输出及本次编码器记录。
        s0_n = 1'b0;
        #1;
        if (pwm !== 4'b0000 || in1 !== 4'b0000 || led[5:4] !== 2'b00) begin
            $display("FAIL: S0 did not clear outputs and diagnostic latch");
            $finish;
        end
        $display("PASS tb_acg720_motor_encoder_direction: one motor, quadrature sign, timeout, reset");
        $finish;
    end
endmodule
