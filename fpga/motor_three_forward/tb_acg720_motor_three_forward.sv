`timescale 1ns/1ps
module tb_acg720_motor_three_forward;
    reg clk = 0;
    reg s0_n = 0;
    reg s1_n = 1;
    reg [3:0] enc_a = 0;
    reg [3:0] enc_b = 0;
    wire [3:0] pwm;
    wire [3:0] in1;
    wire [3:0] in2;
    wire [5:0] led;
    wire tx;
    integer wheel;
    integer phase = 0;
    integer phase_div = 0;
    integer i;

    always #5 clk = ~clk;
    acg720_motor_three_forward #(
        .CLK_HZ(10000), .PWM_HZ(1000), .BAUD(1000),
        .STARTUP_MS(2), .DEBOUNCE_MS(2),
        .KICK_MS(10), .RUN_MAX_MS(170), .LOSS_TICKS(4)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .encoder_a_i(enc_a), .encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .uart_tx_o(tx)
    );

    // M2/M4 保持原方向，M3 反转后模拟原始编码器符号变化。
    always @(negedge clk) begin
        if ((in1 | in2) != 0) begin
            if (phase_div == 3) begin
                phase_div = 0;
                phase = (phase + 1) % 4;
                for (i = 1; i < 4; i = i + 1) begin
                    if (in1[i] || in2[i]) begin
                        case (phase)
                            0: begin enc_a[i] = 0; enc_b[i] = 0; end
                            1: begin enc_a[i] = 0; enc_b[i] = 1; end
                            2: begin enc_a[i] = 1; enc_b[i] = 1; end
                            3: begin enc_a[i] = 1; enc_b[i] = 0; end
                        endcase
                    end
                end
            end else phase_div = phase_div + 1;
        end
    end

    task press_s1;
        begin
            s1_n = 0;
            repeat (30) @(posedge clk);
            s1_n = 1;
            repeat (20) @(posedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        s0_n = 1;
        repeat (50) @(posedge clk);
        if (in1 !== 0 || in2 !== 0 || pwm !== 0) begin
            $display("FAIL: unsafe idle"); $finish;
        end
        for (wheel = 1; wheel < 4; wheel = wheel + 1) begin
            press_s1();
            if (in1 !== (wheel == 2 ? 4'b0000 : (4'b0001 << wheel)) ||
                in2 !== (wheel == 2 ? 4'b0100 : 4'b0000) || pwm[0] !== 0) begin
                $display("FAIL: forward direction or wheel selection %0d", wheel+1); $finish;
            end
            repeat (1900) @(posedge clk);
            if (in1 !== 0 || in2 !== 0 || pwm !== 0 || led[3] !== 1 || led[5] !== 0) begin
                $display("FAIL: hard timeout or fault %0d", wheel+1); $finish;
            end
        end
        s0_n = 0;
        #1;
        if (in1 !== 0 || in2 !== 0 || pwm !== 0 || tx !== 1) begin
            $display("FAIL: S0 emergency stop"); $finish;
        end
        $display("PASS tb_acg720_motor_three_forward: M3 reversed only, isolated, timeout, S0");
        $finish;
    end
endmodule
