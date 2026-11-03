`timescale 1ns/1ps
module tb_acg720_motor_bt_drive;
    localparam integer CPB = 10;
    reg clk = 0;
    reg s0_n = 0;
    reg bt_rx = 1;
    reg [3:0] enc_a = 0;
    reg [3:0] enc_b = 0;
    wire [3:0] pwm, in1, in2;
    wire [5:0] led;
    wire diag_tx;
    wire bt_tx;
    integer phase [0:3];
    integer divider [0:3];
    integer i;
    reg positive_raw;
    reg physical_forward;

    always #5 clk = ~clk;
    acg720_motor_bt_drive #(
        .CLK_HZ(10000), .PWM_HZ(1000), .BT_BAUD(1000), .DIAG_BAUD(1000),
        .STARTUP_MS(2), .RUN_LIMIT_MS(500),
        .STAGGER_MS(0), .KICK_MS(10), .TARGET_COUNTS(20),
        .LOSS_TICKS(100), .BT_TIMEOUT_MS(60), .NEUTRAL_MS(10)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n),
        .bt_uart_rx_i(bt_rx), .imu_uart_rx_i(1'b1), .tof0_uart_rx_i(1'b1),
        .encoder_a_i(enc_a), .encoder_b_i(enc_b),
        .motor_pwm_o(pwm), .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .diag_uart_tx_o(diag_tx), .bt_uart_tx_o(bt_tx)
    );

    // 随当前物理驱动方向生成编码器四倍频；前进极性与 4CL2 上板记录一致。
    always @(negedge clk) begin
        for (integer w = 0; w < 4; w = w + 1) begin
            if (in1[w] || in2[w]) begin
                if (divider[w] >= 3) begin
                    divider[w] = 0;
                    phase[w] = (phase[w] + 1) % 4;
                    physical_forward = (w == 0 || w == 2) ? in2[w] : in1[w];
                    positive_raw = (w == 0 || w == 2) ? physical_forward : !physical_forward;
                    if (positive_raw) begin
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

    task send_byte(input [7:0] value, input good_stop);
        integer b;
        begin
            @(negedge clk); bt_rx = 0;
            repeat (CPB) @(negedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                bt_rx = value[b];
                repeat (CPB) @(negedge clk);
            end
            bt_rx = good_stop;
            repeat (CPB) @(negedge clk);
            bt_rx = 1;
            repeat (10) @(posedge clk);
        end
    endtask

    task expect_dir(input [3:0] expected_in1, input [3:0] expected_in2);
        begin
            repeat (5) @(posedge clk);
            if (in1 !== expected_in1 || in2 !== expected_in2 || pwm === 4'bxxxx) begin
                $display("FAIL direction: expected %b/%b got %b/%b cmd=%0d", expected_in1, expected_in2, in1, in2, dut.command);
                $finish;
            end
        end
    endtask

    initial begin
        for (i = 0; i < 4; i = i + 1) begin phase[i] = 0; divider[i] = 0; end
        repeat (5) @(posedge clk);
        send_byte("F", 1);
        expect_dir(0, 0);
        s0_n = 1;
        repeat (50) @(posedge clk);
        send_byte("1", 1);
        if (dut.target_counts !== 12) begin $display("FAIL stopped speed selection"); $finish; end
        repeat (120) @(posedge clk);
        send_byte("X", 1);
        expect_dir(0, 0);
        send_byte("F", 1); // 复位后持续方向字节不能自行启动
        expect_dir(0, 0);
        send_byte("S", 1); // 明确停车后才可重新使能
        repeat (120) @(posedge clk);
        send_byte("F", 1);
        expect_dir(4'b1010, 4'b0101);
        send_byte("3", 1);
        if (dut.target_counts !== 12) begin $display("FAIL moving speed change accepted"); $finish; end
        repeat (220) @(posedge clk);
        for (i = 0; i < 4; i = i + 1) begin
            if (dut.speed[i] <= 0) begin $display("FAIL F feedback M%0d=%0d", i+1, dut.speed[i]); $finish; end
        end
        send_byte("S", 1); expect_dir(0, 0);
        send_byte("2", 1);
        if (dut.target_counts !== 16) begin $display("FAIL stopped speed selection"); $finish; end
        send_byte("9", 1);
        if (dut.target_counts !== 16) begin $display("FAIL invalid speed changed target"); $finish; end
        repeat (120) @(posedge clk);
        send_byte("B", 1); expect_dir(4'b0101, 4'b1010);
        repeat (220) @(posedge clk);
        for (i = 0; i < 4; i = i + 1) begin
            if (dut.speed[i] <= 0) begin $display("FAIL B feedback M%0d=%0d", i+1, dut.speed[i]); $finish; end
        end
        send_byte("S", 1); expect_dir(0, 0);
        repeat (120) @(posedge clk);
        send_byte("L", 1); expect_dir(4'b1100, 4'b0011);
        repeat (220) @(posedge clk);
        for (i = 0; i < 4; i = i + 1) begin
            if (dut.speed[i] <= 0) begin $display("FAIL L feedback M%0d=%0d", i+1, dut.speed[i]); $finish; end
        end
        send_byte("R", 1); expect_dir(0, 0);
        repeat (120) @(posedge clk);
        send_byte("R", 1); expect_dir(0, 0);
        send_byte("S", 1);
        repeat (120) @(posedge clk);
        send_byte("R", 1); expect_dir(4'b0011, 4'b1100);
        repeat (220) @(posedge clk);
        for (i = 0; i < 4; i = i + 1) begin
            if (dut.speed[i] <= 0) begin $display("FAIL R feedback M%0d=%0d", i+1, dut.speed[i]); $finish; end
        end
        repeat (650) @(posedge clk);
        if (pwm !== 0 || in1 !== 0 || in2 !== 0 || led[5] !== 1) begin
            $display("FAIL Bluetooth timeout all-stop led=%b", led); $finish;
        end
        send_byte("F", 1); expect_dir(0, 0);
        send_byte("S", 1);
        repeat (120) @(posedge clk);
        send_byte("F", 1); expect_dir(4'b1010, 4'b0101);
        s0_n = 0; #1;
        if (pwm !== 0 || in1 !== 0 || in2 !== 0) begin
            $display("FAIL asynchronous S0 stop"); $finish;
        end
        repeat (10) @(posedge clk); s0_n = 1;
        repeat (120) @(posedge clk);
        send_byte("F", 1);
        expect_dir(0, 0); // S0 松开时 GUI 仍按住 F，也必须保持停车
        send_byte("S", 1);
        repeat (120) @(posedge clk);
        send_byte("F", 1);
        expect_dir(4'b1010, 4'b0101);
        send_byte("F", 0);
        if (pwm !== 0 || in1 !== 0 || in2 !== 0 || led[5] !== 1) begin
            $display("FAIL UART framing all-stop led=%b", led); $finish;
        end
        // 持续刷新的合法方向命令应续期，不应被 3 s 启动保护计时器误停；
        // 随后显式 S 仍必须立即停车。
        s0_n = 0; repeat (10) @(posedge clk); s0_n = 1;
        repeat (120) @(posedge clk);
        send_byte("S", 1);
        repeat (120) @(posedge clk);
        for (i = 0; i < 14; i = i + 1) begin
            send_byte("F", 1);
            repeat (400) @(posedge clk);
        end
        if (in1 === 0 || in2 === 0) begin
            $display("FAIL repeated direction refresh was stopped by run limit led=%b", led); $finish;
        end
        send_byte("S", 1);
        repeat (20) @(posedge clk);
        if (pwm !== 0 || in1 !== 0 || in2 !== 0) begin
            $display("FAIL explicit S did not stop refreshed motion led=%b", led); $finish;
        end
        $display("PASS tb_acg720_motor_bt_drive: direct GUI F/B/L/R, speed presets, feedback, stop-first, watchdog, S0, framing fault, lease refresh");
        $finish;
    end
endmodule
