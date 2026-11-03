`timescale 1ns/1ps
module tb_acg720_motor_encoder_decimal;
    reg clk = 1'b0;
    reg s0_n = 1'b0;
    reg s1_n = 1'b1;
    reg enc_a = 1'b0;
    reg enc_b = 1'b0;
    wire [3:0] pwm;
    wire [3:0] in1;
    wire [3:0] in2;
    wire [5:0] led;
    wire ds, sh, st;
    integer phase = 0;
    integer measured;

    always #5 clk = ~clk;

    acg720_motor_encoder_decimal #(
        .CLK_HZ(1000), .PWM_HZ(100), .STARTUP_MS(2),
        .DEBOUNCE_MS(2), .KICK_MS(10), .RUN_MAX_MS(70),
        .SAMPLE_START_MS(20)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_encoder_a_i(enc_a), .m1_encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .seg_ds_o(ds), .seg_sh_cp_o(sh), .seg_st_cp_o(st),
        .decimal_hundreds_o(), .decimal_tens_o(), .decimal_ones_o(),
        .decimal_negative_o(), .decimal_overflow_o(), .decimal_done_o()
    );

    // 模拟 M1 前进负计数的四相变化，输入在时钟下降沿更新以避开测试竞争。
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
            $display("FAIL: initial state unsafe"); $finish;
        end
        s1_n = 1'b0;
        repeat (7) @(posedge clk);
        s1_n = 1'b1;
        repeat (8) @(posedge clk);
        if (in1 !== 4'b0001 || in2 !== 0 || pwm[3:1] !== 0) begin
            $display("FAIL: only M1 should run"); $finish;
        end
        repeat (115) @(posedge clk);
        measured = dut.hundreds * 100 + dut.tens * 10 + dut.ones;
        if (in1 !== 0 || in2 !== 0 || pwm !== 0 || led[3] !== 1'b1 ||
            led[4] !== 1'b1 || measured < 8 || measured > 12) begin
            $display("FAIL: rate display or timeout, value=%0d", measured); $finish;
        end
        repeat (10) @(posedge clk);
        if (dut.hundreds * 100 + dut.tens * 10 + dut.ones !== measured) begin
            $display("FAIL: decimal reading not held"); $finish;
        end
        s0_n = 1'b0;
        #1;
        if (pwm !== 0 || in1 !== 0 || dut.ones !== 0 || dut.tens !== 0) begin
            $display("FAIL: reset did not clear motor and meter"); $finish;
        end
        $display("PASS tb_acg720_motor_encoder_decimal: one motor, decimal rate=%0d, timeout, reset", measured);
        $finish;
    end
endmodule
