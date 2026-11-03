`timescale 1ns/1ps
module tb_acg720_motor_three_calibrate;
    reg clk = 0;
    reg s0_n = 0;
    reg s1_n = 1;
    reg [3:0] enc_a = 0;
    reg [3:0] enc_b = 0;
    reg plant_enabled = 1;
    wire [3:0] pwm;
    wire [3:0] in1;
    wire [3:0] in2;
    wire [5:0] led;
    wire tx;
    integer phase = 0;
    integer div_count = 0;
    integer i;
    integer wheel;
    reg [7:0] rx_byte [0:26];
    reg [7:0] sampled_byte;
    integer rx_count = 0;
    integer bit_index;

    always #5 clk = ~clk;

    acg720_motor_three_calibrate #(
        .CLK_HZ(10000), .PWM_HZ(1000), .BAUD(1000),
        .STARTUP_MS(2), .DEBOUNCE_MS(2),
        .KICK_MS(10), .RUN_MAX_MS(170), .LOSS_TICKS(4)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n), .key_s1_n_i(s1_n),
        .encoder_a_i(enc_a), .encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .uart_tx_o(tx)
    );

    // 只有当前通道的编码器变化，检查串扰和轮号选择。
    always @(negedge clk) begin
        if (plant_enabled && in1 != 0) begin
            if (div_count == 3) begin
                div_count = 0;
                phase = (phase + 1) % 4;
                for (i = 0; i < 4; i = i + 1) begin
                    if (in1[i]) begin
                        case (phase)
                            0: begin enc_a[i] = 0; enc_b[i] = 0; end
                            1: begin enc_a[i] = 0; enc_b[i] = 1; end
                            2: begin enc_a[i] = 1; enc_b[i] = 1; end
                            3: begin enc_a[i] = 1; enc_b[i] = 0; end
                        endcase
                    end
                end
            end else div_count = div_count + 1;
        end
    end
    // 完整采样三次轮号报文，确保 M2、M3、M4 不会串号。
    always @(negedge tx) begin
        if (s0_n && rx_count < 27) begin
            #50;
            if (tx !== 0) begin $display("FAIL: UART start bit"); $finish; end
            sampled_byte = 0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #100;
                sampled_byte[bit_index] = tx;
            end
            #100;
            if (tx !== 1) begin $display("FAIL: UART stop bit"); $finish; end
            rx_byte[rx_count] = sampled_byte;
            rx_count = rx_count + 1;
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
        if (pwm !== 0 || in1 !== 0 || in2 !== 0 || tx !== 1) begin
            $display("FAIL: unsafe idle output"); $finish;
        end
        for (wheel = 1; wheel < 4; wheel = wheel + 1) begin
            press_s1();
            if (in1 !== (4'b0001 << wheel) || in2 !== 0 ||
                pwm[0] !== 0 || dut.wheel_index !== wheel) begin
                $display("FAIL: selected wheel %0d, in1=%b", wheel+1, in1); $finish;
            end
            repeat (1900) @(posedge clk);
            if (in1 !== 0 || pwm !== 0 || led[3] !== 1 ||
                led[5] !== 0 || dut.wheel_index !== (wheel == 3 ? 1 : wheel+1)) begin
                $display("FAIL: timeout or next-wheel selection at wheel %0d", wheel+1); $finish;
            end
        end
        if (rx_count !== 27 || led[4] !== 1) begin
            $display("FAIL: telemetry or encoder feedback missing, rx_count=%0d", rx_count); $finish;
        end
        for (wheel = 0; wheel < 3; wheel = wheel + 1) begin
            if (rx_byte[wheel*9] !== "M" || rx_byte[wheel*9+1] !== ("2" + wheel) ||
                rx_byte[wheel*9+2] !== ":" || rx_byte[wheel*9+3] !== "+" ||
                rx_byte[wheel*9+7] !== 8'h0d || rx_byte[wheel*9+8] !== 8'h0a) begin
                $display("FAIL: UART wheel frame %0d", wheel+2); $finish;
            end
        end
        s0_n = 0;
        #1;
        if (in1 !== 0 || pwm !== 0 || tx !== 1) begin
            $display("FAIL: S0 emergency stop"); $finish;
        end
        repeat (10) @(posedge clk);
        s0_n = 1;
        repeat (50) @(posedge clk);
        plant_enabled = 0;
        press_s1();
        repeat (900) @(posedge clk);
        if (led[5] !== 1 || in1 !== 0 || pwm !== 0) begin
            $display("FAIL: encoder-loss fault"); $finish;
        end
        $display("PASS tb_acg720_motor_three_calibrate: M2/M3/M4 one-at-a-time, timeout, feedback, fault, reset");
        $finish;
    end
endmodule
