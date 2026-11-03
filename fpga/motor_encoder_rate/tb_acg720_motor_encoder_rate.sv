`timescale 1ns/1ps
module tb_acg720_motor_encoder_rate;
    reg clk = 1'b0;
    reg s0_n = 1'b0;
    reg s1_n = 1'b1;
    reg enc_a = 1'b0;
    reg enc_b = 1'b0;
    wire [3:0] pwm;
    wire [3:0] in1;
    wire [3:0] in2;
    wire [5:0] led;
    integer phase = 0;
    integer observed_code;

    always #5 clk = ~clk;

    // 缩短物理时间常数验证测试流程，四相仍由 FPGA 同步解码。
    acg720_motor_encoder_rate #(
        .CLK_HZ(1000), .PWM_HZ(100), .STARTUP_MS(2),
        .DEBOUNCE_MS(2), .KICK_MS(10), .RUN_MAX_MS(70),
        .SAMPLE_START_MS(20)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_encoder_a_i(enc_a), .m1_encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2), .led_o(led)
    );

    // 00→10→11→01→00：与 M1 实测车辆前进方向一致，为负计数。
    always @(negedge clk) begin
        if (in1[0]) begin
            phase = (phase + 1) % 4;
            case (phase)
                0: begin enc_a = 0; enc_b = 0; end
                1: begin enc_a = 1; enc_b = 0; end
                2: begin enc_a = 1; enc_b = 1; end
                3: begin enc_a = 0; enc_b = 1; end
            endcase
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        s0_n = 1'b1;
        repeat (10) @(posedge clk);
        if (led[1] !== 1'b1 || in1 !== 0 || pwm !== 0) begin
            $display("FAIL: initial state is not safe");
            $finish;
        end

        s1_n = 1'b0;
        repeat (7) @(posedge clk);
        s1_n = 1'b1;
        repeat (8) @(posedge clk);
        if (in1 !== 4'b0001 || in2 !== 0 || pwm[3:1] !== 0) begin
            $display("FAIL: only M1 should run");
            $finish;
        end

        repeat (90) @(posedge clk);
        observed_code = led;
        if (in1 !== 0 || in2 !== 0 || pwm !== 0 || observed_code < 1 || observed_code > 10) begin
            $display("FAIL: timeout or rate display wrong, code=%0d", observed_code);
            $finish;
        end

        // 超时读数需锁存，直到复位或下次试转。
        repeat (10) @(posedge clk);
        if (led !== observed_code) begin
            $display("FAIL: measured code did not hold");
            $finish;
        end
        s0_n = 1'b0;
        #1;
        if (pwm !== 0 || in1 !== 0 || led[5:4] !== 0) begin
            $display("FAIL: reset did not stop/clear");
            $finish;
        end
        $display("PASS tb_acg720_motor_encoder_rate: one motor, signed-count magnitude, timeout, LED code=%0d", observed_code);
        $finish;
    end
endmodule
