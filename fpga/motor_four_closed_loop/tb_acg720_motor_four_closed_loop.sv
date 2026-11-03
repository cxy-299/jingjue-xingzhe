`timescale 1ns/1ps
module tb_acg720_motor_four_closed_loop;
    reg clk = 0;
    reg s0_n = 0;
    reg s1_n = 1;
    reg [3:0] enc_a = 0;
    reg [3:0] enc_b = 0;
    reg [3:0] plant_enabled = 4'b1111;
    reg [3:0] invert_encoder = 0;
    wire [3:0] pwm, in1, in2;
    wire [5:0] led;
    wire uart_tx;
    integer phase [0:3];
    integer divider [0:3];
    integer phase_interval = 4;
    integer duty_fast [0:3];
    integer i;
    integer frames_seen [0:3];
    integer serial_bytes = 0;
    integer bit_index;
    reg [7:0] serial_byte;
    reg [7:0] frame [0:23];

    // S0 可中断一帧；复位后串口接收也从新的帧头重新计数。
    always @(negedge s0_n) serial_bytes = 0;

    always #5 clk = ~clk;
    acg720_motor_four_closed_loop #(
        .CLK_HZ(10000), .PWM_HZ(1000), .BAUD(1000),
        .STARTUP_MS(2), .DEBOUNCE_MS(2), .RUN_MAX_MS(1400),
        .STAGGER_MS(30), .KICK_MS(20), .TARGET_COUNTS(20), .LOSS_TICKS(4)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .encoder_a_i(enc_a), .encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .uart_tx_o(uart_tx)
    );

    // 修正后 M1/M3 用正计数相序，M2/M4 用负计数相序；每路均产生有效反馈。
    always @(negedge clk) begin
        for (integer w = 0; w < 4; w = w + 1) begin
            if ((in1[w] || in2[w]) && plant_enabled[w]) begin
                if (divider[w] >= phase_interval - 1) begin
                    divider[w] = 0;
                    phase[w] = (phase[w] + 1) % 4;
                    if (((w == 0) || (w == 2)) ^ invert_encoder[w]) begin
                        case (phase[w])
                            0: begin enc_a[w] = 0; enc_b[w] = 0; end
                            1: begin enc_a[w] = 0; enc_b[w] = 1; end
                            2: begin enc_a[w] = 1; enc_b[w] = 1; end
                            3: begin enc_a[w] = 1; enc_b[w] = 0; end
                        endcase
                    end else begin
                        case (phase[w])
                            0: begin enc_a[w] = 0; enc_b[w] = 0; end
                            1: begin enc_a[w] = 1; enc_b[w] = 0; end
                            2: begin enc_a[w] = 1; enc_b[w] = 1; end
                            3: begin enc_a[w] = 0; enc_b[w] = 1; end
                        endcase
                    end
                end else divider[w] = divider[w] + 1;
            end
        end
    end

    // 每帧核对 M1～M4 轮询及速度、占空比、故障字段的完整位置。
    always @(negedge uart_tx) begin
        if (s0_n) begin
            #50;
            if (uart_tx !== 0) begin $display("FAIL UART start"); $finish; end
            serial_byte = 0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #100;
                serial_byte[bit_index] = uart_tx;
            end
            #100;
            if (uart_tx !== 1) begin $display("FAIL UART stop"); $finish; end
            frame[serial_bytes % 24] = serial_byte;
            serial_bytes = serial_bytes + 1;
            if (serial_bytes % 24 == 0) begin
                if (frame[0] !== "M" || frame[1] < "1" || frame[1] > "4" ||
                    frame[3] !== "T" || frame[8] !== "A" || frame[14] !== "D" ||
                    frame[20] !== "F" || frame[22] !== 8'h0d || frame[23] !== 8'h0a) begin
                    $display("FAIL UART frame %0d", serial_bytes / 24); $finish;
                end
                frames_seen[frame[1]-"1"] = frames_seen[frame[1]-"1"] + 1;
            end
        end
    end

    task press_s1;
        begin
            s1_n = 0; repeat (30) @(posedge clk);
            s1_n = 1; repeat (20) @(posedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            phase[i] = 0; divider[i] = 0; frames_seen[i] = 0;
        end
        repeat (5) @(posedge clk);
        s0_n = 1;
        repeat (50) @(posedge clk);
        if (pwm !== 0 || in1 !== 0 || in2 !== 0 || uart_tx !== 1) begin
            $display("FAIL idle outputs"); $finish;
        end
        press_s1();
        repeat (10) @(posedge clk);
        if (in1 !== 0 || in2 !== 4'b0001) begin
            $display("FAIL stagger M1"); $finish;
        end
        repeat (300) @(posedge clk);
        if (in1 !== 4'b0010 || in2 !== 4'b0001) begin
            $display("FAIL stagger M2"); $finish;
        end
        repeat (300) @(posedge clk);
        if (in1 !== 4'b0010 || in2 !== 4'b0101) begin
            $display("FAIL M3 direction"); $finish;
        end
        repeat (300) @(posedge clk);
        if (in1 !== 4'b1010 || in2 !== 4'b0101) begin
            $display("FAIL M4 direction"); $finish;
        end
        repeat (650) @(posedge clk);
        if (led[4] !== 1 || led[5] !== 0) begin
            $display("FAIL all feedback or false fault: led=%b", led); $finish;
        end
        // 四轮加速时 PI 应降低占空比，模拟减速后应再次提高占空比。
        phase_interval = 3;
        repeat (500) @(posedge clk);
        for (i = 0; i < 4; i = i + 1) duty_fast[i] = dut.duty[i];
        phase_interval = 5;
        repeat (500) @(posedge clk);
        for (i = 0; i < 4; i = i + 1) begin
            if (dut.duty[i] <= duty_fast[i] || dut.duty[i] > 850) begin
                $display("FAIL M%0d PI response fast=%0d slow=%0d led=%b speed=%0d enable=%b fault=%b", i+1, duty_fast[i], dut.duty[i], led, dut.speed[i], dut.channel_enable, dut.channel_fault); $finish;
            end
        end
        repeat (13300) @(posedge clk);
        if (in1 !== 0 || in2 !== 0 || pwm !== 0 || led[3] !== 1) begin
            $display("FAIL hard timeout"); $finish;
        end
        for (i = 0; i < 4; i = i + 1) begin
            if (frames_seen[i] == 0) begin
                $display("FAIL missing UART M%0d", i+1); $finish;
            end
        end
        s0_n = 0; #1;
        if (in1 !== 0 || in2 !== 0 || pwm !== 0 || uart_tx !== 1) begin
            $display("FAIL S0 asynchronous stop"); $finish;
        end
        repeat (10) @(posedge clk); s0_n = 1;
        repeat (50) @(posedge clk);
        plant_enabled[2] = 0;
        press_s1();
        repeat (1800) @(posedge clk);
        if (led[5] !== 1 || pwm !== 0 || in1 !== 0 || in2 !== 0) begin
            $display("FAIL M3 feedback loss all-stop: led=%b", led); $finish;
        end
        // 再模拟 M2 编码器 A/B 颠倒，连续反向计数必须触发四路共同停机。
        s0_n = 0; repeat (10) @(posedge clk); s0_n = 1;
        repeat (50) @(posedge clk);
        plant_enabled = 4'b1111;
        invert_encoder[1] = 1;
        press_s1();
        repeat (1200) @(posedge clk);
        if (led[5] !== 1 || pwm !== 0 || in1 !== 0 || in2 !== 0) begin
            $display("FAIL M2 reversed feedback all-stop: led=%b", led); $finish;
        end
        $display("PASS tb_acg720_motor_four_closed_loop: directions, stagger, four PI, UART, timeout, S0, missing/reversed feedback all-stop");
        $finish;
    end
endmodule
