`timescale 1ns/1ps
module tb_acg720_motor_encoder_uart;
    reg clk = 1'b0;
    reg s0_n = 1'b0;
    reg s1_n = 1'b1;
    reg enc_a = 1'b0;
    reg enc_b = 1'b0;
    wire [3:0] pwm;
    wire [3:0] in1;
    wire [3:0] in2;
    wire [5:0] led;
    wire uart_tx;
    reg [7:0] received [0:8];
    integer received_count = 0;
    integer phase = 0;
    integer bit_index;
    reg [7:0] byte_value;

    always #5 clk = ~clk;

    acg720_motor_encoder_uart #(
        .CLK_HZ(1000), .BAUD(100), .PWM_HZ(100),
        .STARTUP_MS(2), .DEBOUNCE_MS(2), .KICK_MS(10),
        .RUN_MAX_MS(70), .SAMPLE_START_MS(20)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .m1_encoder_a_i(enc_a), .m1_encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .uart_tx_o(uart_tx)
    );

    // M1 车辆前进方向按已经上板确认的负计数相序输入。
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

    // 以 UART 位中心采样，验证 8-N-1 帧和完整 ASCII 行。
    always @(negedge uart_tx) begin
        if (s0_n && received_count < 9) begin
            #50;
            if (uart_tx !== 1'b0) begin
                $display("FAIL: UART start bit"); $finish;
            end
            byte_value = 8'h00;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #100;
                byte_value[bit_index] = uart_tx;
            end
            #100;
            if (uart_tx !== 1'b1) begin
                $display("FAIL: UART stop bit"); $finish;
            end
            received[received_count] = byte_value;
            received_count = received_count + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        s0_n = 1'b1;
        repeat (10) @(posedge clk);
        if (in1 !== 0 || pwm !== 0 || uart_tx !== 1'b1) begin
            $display("FAIL: unsafe initial state"); $finish;
        end
        s1_n = 1'b0;
        repeat (7) @(posedge clk);
        s1_n = 1'b1;
        repeat (8) @(posedge clk);
        if (in1 !== 4'b0001 || in2 !== 0 || pwm[3:1] !== 0) begin
            $display("FAIL: only M1 should run"); $finish;
        end
        repeat (1200) @(posedge clk);
        if (in1 !== 0 || in2 !== 0 || pwm !== 0 || led[3] !== 1'b1 ||
            received_count !== 9) begin
            $display("FAIL: timeout or 9-byte telemetry, got %0d bytes", received_count);
            $finish;
        end
        if (received[0] !== "M" || received[1] !== "1" ||
            received[2] !== ":" || received[3] !== "-" ||
            received[4] < "0" || received[4] > "9" ||
            received[5] < "0" || received[5] > "9" ||
            received[6] < "0" || received[6] > "9" ||
            received[7] !== 8'h0d || received[8] !== 8'h0a) begin
            $display("FAIL: telemetry frame %c%c%c%c%c%c%c %02x %02x",
                     received[0],received[1],received[2],received[3],
                     received[4],received[5],received[6],received[7],received[8]);
            $finish;
        end
        s0_n = 1'b0;
        #1;
        if (in1 !== 0 || pwm !== 0 || uart_tx !== 1'b1) begin
            $display("FAIL: reset must stop motor and UART"); $finish;
        end
        $display("PASS tb_acg720_motor_encoder_uart: M1 hard timeout, UART frame M1:-%c%c%c, reset",
                 received[4],received[5],received[6]);
        $finish;
    end
endmodule
