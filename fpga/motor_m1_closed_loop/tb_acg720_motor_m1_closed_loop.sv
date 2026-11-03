`timescale 1ns/1ps
module tb_acg720_motor_m1_closed_loop;
    reg clk = 0;
    reg s0_n = 0;
    reg s1_n = 1;
    reg enc_a = 0;
    reg enc_b = 0;
    reg plant_enabled = 1;
    integer phase_interval = 3;
    integer phase_div = 0;
    integer phase = 0;
    wire [3:0] pwm;
    wire [3:0] in1;
    wire [3:0] in2;
    wire [5:0] led;
    wire uart_tx;
    integer duty_fast;
    integer duty_slow;
    reg [7:0] received [0:23];
    integer received_count = 0;
    integer bit_index;
    reg [7:0] byte_value;

    always #5 clk = ~clk;

    acg720_motor_m1_closed_loop #(
        .CLK_HZ(10000), .PWM_HZ(1000), .BAUD(1000),
        .STARTUP_MS(2), .DEBOUNCE_MS(2), .RUN_MAX_MS(350),
        .KICK_MS(20), .TARGET_COUNTS(20), .LOSS_TICKS(4)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_encoder_a_i(enc_a), .m1_encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .uart_tx_o(uart_tx)
    );

    // 模拟 M1 正转的负计数相序；间隔变短表示轮速升高。
    always @(negedge clk) begin
        if (in1[0] && plant_enabled) begin
            if (phase_div >= phase_interval - 1) begin
                phase_div = 0;
                phase = (phase + 1) % 4;
                case (phase)
                    0: begin enc_a = 0; enc_b = 0; end
                    1: begin enc_a = 1; enc_b = 0; end
                    2: begin enc_a = 1; enc_b = 1; end
                    3: begin enc_a = 0; enc_b = 1; end
                endcase
            end else phase_div = phase_div + 1;
        end
    end

    // 按 UART 位中心采样第一帧，检查目标、方向、占空比和故障字段的位置。
    always @(negedge uart_tx) begin
        if (s0_n && received_count < 24) begin
            #50;
            if (uart_tx !== 0) begin
                $display("FAIL: UART start bit"); $finish;
            end
            byte_value = 0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #100;
                byte_value[bit_index] = uart_tx;
            end
            #100;
            if (uart_tx !== 1) begin
                $display("FAIL: UART stop bit"); $finish;
            end
            received[received_count] = byte_value;
            received_count = received_count + 1;
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
        if (in1 !== 0 || in2 !== 0 || pwm !== 0 || uart_tx !== 1) begin
            $display("FAIL: initial output is not safe"); $finish;
        end
        press_s1();
        if (in1 !== 4'b0001 || in2 !== 0 || pwm[3:1] !== 0) begin
            $display("FAIL: only M1 should run"); $finish;
        end
        repeat (700) @(posedge clk);
        if (led[4] !== 1 || led[5] !== 0 || dut.forward_speed <= 0) begin
            $display("FAIL: forward feedback polarity or fault, speed=%0d", dut.forward_speed); $finish;
        end
        phase_interval = 2;
        repeat (400) @(posedge clk);
        duty_fast = dut.duty_permille;
        phase_interval = 4;
        repeat (400) @(posedge clk);
        duty_slow = dut.duty_permille;
        if (duty_slow <= duty_fast || duty_fast < 300 || duty_slow > 850) begin
            $display("FAIL: PI duty response fast=%0d slow=%0d", duty_fast, duty_slow); $finish;
        end
        repeat (2500) @(posedge clk);
        if (in1 !== 0 || pwm !== 0 || led[3] !== 1) begin
            $display("FAIL: hard timeout did not stop M1"); $finish;
        end
        if (received_count !== 24 || received[0] !== "M" || received[1] !== "1" ||
            received[3] !== "T" || received[4] !== "0" || received[5] !== "2" ||
            received[6] !== "0" || received[8] !== "A" || received[9] !== "+" ||
            received[14] !== "D" || received[20] !== "F" || received[21] !== "0" ||
            received[22] !== 8'h0d || received[23] !== 8'h0a) begin
            $display("FAIL: UART telemetry format, count=%0d", received_count); $finish;
        end
        s0_n = 0;
        #1;
        if (in1 !== 0 || pwm !== 0 || uart_tx !== 1) begin
            $display("FAIL: S0 must stop outputs asynchronously"); $finish;
        end
        repeat (10) @(posedge clk);
        s0_n = 1;
        repeat (50) @(posedge clk);
        plant_enabled = 0;
        press_s1();
        repeat (900) @(posedge clk);
        if (led[5] !== 1 || in1 !== 0 || pwm !== 0) begin
            $display("FAIL: encoder loss did not latch fault"); $finish;
        end
        $display("PASS tb_acg720_motor_m1_closed_loop: sign, PI response, timeout, S0, encoder loss");
        $finish;
    end
endmodule
