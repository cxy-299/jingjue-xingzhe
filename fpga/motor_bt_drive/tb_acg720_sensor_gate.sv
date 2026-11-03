`timescale 1ns/1ps
// 统一传感器门控回归：无 ToF 帧时停机，收到有效距离后允许蓝牙前进。
module tb_acg720_sensor_gate;
    reg clk = 0, key_n = 0, bt_rx = 1, tof_rx = 1, imu_rx = 1;
    reg [3:0] enc_a = 0, enc_b = 0;
    wire [3:0] pwm, in1, in2;
    wire [5:0] led;
    wire diag_tx, bt_tx;
    always #500 clk = ~clk; // 1 MHz

    acg720_motor_bt_drive #(
        .CLK_HZ(1_000_000), .PWM_HZ(2_000), .BT_BAUD(10_000),
        .DIAG_BAUD(20_000), .SENSOR_IMU_BAUD(9_600), .SENSOR_TOF_BAUD(10_000),
        .STARTUP_MS(1), .STAGGER_MS(1), .KICK_MS(1), .TARGET_COUNTS(4),
        .BT_TIMEOUT_MS(300), .NEUTRAL_MS(1), .RUN_LIMIT_MS(3000), .NAV_ENABLE(0), .SENSOR_ENABLE(1)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(key_n), .bt_uart_rx_i(bt_rx),
        .imu_uart_rx_i(imu_rx), .tof0_uart_rx_i(tof_rx),
        .encoder_a_i(enc_a), .encoder_b_i(enc_b), .motor_pwm_o(pwm),
        .motor_in1_o(in1), .motor_in2_o(in2), .led_o(led),
        .diag_uart_tx_o(diag_tx), .bt_uart_tx_o(bt_tx)
    );

    task automatic send_tof_byte(input [7:0] value);
        integer b;
        begin
            tof_rx = 0; #100000;
            for (b = 0; b < 8; b = b + 1) begin tof_rx = value[b]; #100000; end
            tof_rx = 1; #100000;
        end
    endtask

    task automatic send_tof_900;
        begin
            send_tof_byte("9"); send_tof_byte("0");
            send_tof_byte("0"); send_tof_byte(8'h0d);
            send_tof_byte(8'h0a);
        end
    endtask

    task automatic send_bt(input [7:0] value);
        integer b;
        begin
            bt_rx = 0; #100000;
            for (b = 0; b < 8; b = b + 1) begin bt_rx = value[b]; #100000; end
            bt_rx = 1; #100000;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk); key_n = 1;
        repeat (1500) @(posedge clk);
        if (!dut.ready || !dut.tof_hard_stop || dut.motor_enable)
            $fatal(1, "sensor gate did not fail safe before ToF frame");
        send_tof_900();
        repeat (10000) @(posedge clk);
        $display("DEBUG tof_valid=%b d=%0d parser_valid=%b rx=%b", dut.tof_valid,
                 dut.tof0_distance_mm, dut.g_sensor_frontend.u_sensor.u_tof0.valid_pulse_o,
                 tof_rx);
        if (dut.tof_hard_stop || !dut.tof_valid[0])
            $fatal(1, "valid ToF frame did not release hard stop");
        send_bt("S"); repeat (2000) @(posedge clk); send_bt("F");
        repeat (300) @(posedge clk);
        if (dut.command != 1 || !dut.motor_enable)
            $fatal(1, "valid ToF did not permit forward command");
        $display("PASS tb_acg720_sensor_gate: ToF fail-safe and release");
        $finish;
    end
endmodule
