`timescale 1ns/1ps
module tb_start_stagger_125;
    localparam integer CPB = 10;
    reg clk = 0;
    reg s0_n = 0;
    reg bt_rx = 1;
    wire [3:0] pwm, in1, in2;
    wire [5:0] led;
    wire diag_tx, bt_tx;
    integer tick;
    integer started [0:3];
    integer i;
    integer active_kicks;

    always #5 clk = ~clk;
    acg720_motor_bt_drive #(
        .CLK_HZ(10_000), .PWM_HZ(1_000), .BT_BAUD(1_000),
        .DIAG_BAUD(1_000), .STARTUP_MS(1),
        .STAGGER_MS(125), .KICK_MS(100),
        .LOSS_TICKS(100), .BT_TIMEOUT_MS(600),
        .NEUTRAL_MS(10), .RUN_LIMIT_MS(1_000)
    ) dut (
        .clk_50m_i(clk), .key_s0_n_i(s0_n),
        .bt_uart_rx_i(bt_rx), .imu_uart_rx_i(1'b1),
        .tof0_uart_rx_i(1'b1), .encoder_a_i(4'b0),
        .encoder_b_i(4'b0), .motor_pwm_o(pwm),
        .motor_in1_o(in1), .motor_in2_o(in2),
        .led_o(led), .diag_uart_tx_o(diag_tx), .bt_uart_tx_o(bt_tx)
    );

    task send_byte(input [7:0] value);
        integer b;
        begin
            @(negedge clk); bt_rx = 0;
            repeat (CPB) @(negedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                bt_rx = value[b];
                repeat (CPB) @(negedge clk);
            end
            bt_rx = 1;
            repeat (CPB + 10) @(negedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 4; i = i + 1) started[i] = -1;
        repeat (10) @(posedge clk); s0_n = 1;
        repeat (30) @(posedge clk);
        send_byte("S");
        repeat (120) @(posedge clk);
        send_byte("F");
        if (!dut.motor_enable) $fatal(1, "F was not accepted");
        for (tick = 0; tick < 4000; tick = tick + 1) begin
            @(posedge clk);
            for (i = 0; i < 4; i = i + 1)
                if (started[i] < 0 && dut.channel_enable[i]) started[i] = tick;
            active_kicks =
                (dut.channel_enable[0] && dut.wheels[0].u_control.kick_active) +
                (dut.channel_enable[1] && dut.wheels[1].u_control.kick_active) +
                (dut.channel_enable[2] && dut.wheels[2].u_control.kick_active) +
                (dut.channel_enable[3] && dut.wheels[3].u_control.kick_active);
            if (active_kicks > 1) $fatal(1, "startup kicks overlapped at %0d", tick);
            if (dut.channel_fault !== 4'b0) $fatal(1, "unexpected PI fault");
        end
        for (i = 0; i < 4; i = i + 1) begin
            // Monitoring starts just after the UART byte completes, so M1
            // has already been enabled for up to one UART bit interval.
            if (started[i] < 0 || (started[i] - started[0]) < i * 1250 - 15 ||
                (started[i] - started[0]) > i * 1250 + 15)
                $fatal(1, "wheel %0d startup tick=%0d baseline=%0d", i, started[i], started[0]);
        end
        send_byte("S");
        repeat (20) @(posedge clk);
        if (pwm !== 4'b0 || in1 !== 4'b0 || in2 !== 4'b0)
            $fatal(1, "S failed to stop all wheels");
        $display("PASS tb_start_stagger_125: kick pulses do not overlap; M3 starts at 250 ms; S stops all");
        $finish;
    end
endmodule
