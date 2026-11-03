`timescale 1ns/1ps
module tb_tof_single_bringup;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg tof_rx = 1;
    wire diag_tx;
    wire [5:0] led;
    reg [7:0] rx_line [0:7];
    integer rx_pos = 0;
    integer saw_0200 = 0;
    integer saw_0000 = 0;
    wire [7:0] diag_byte;
    wire diag_valid;
    wire diag_error;

    tof_single_bringup #(.CLK_HZ(100_000), .TOF_BAUD(10_000),
                         .DIAG_BAUD(10_000)) dut (
        .clk_50m_i(clk), .key_s0_n_i(rst_n), .tof_uart_rx_i(tof_rx),
        .diag_uart_tx_o(diag_tx), .led_o(led)
    );
    uart_rx #(.CLK_HZ(100_000), .BAUD(10_000)) diag_receiver (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(diag_tx),
        .data_o(diag_byte), .data_valid_o(diag_valid),
        .framing_error_o(diag_error)
    );

    task send_char(input [7:0] value);
        integer bit_no;
        begin
            tof_rx = 0;
            repeat (10) @(negedge clk);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                tof_rx = value[bit_no];
                repeat (10) @(negedge clk);
            end
            tof_rx = 1;
            repeat (10) @(negedge clk);
        end
    endtask

    task send_distance(input [7:0] c0, c1, c2);
        begin
            send_char(c0); send_char(c1); send_char(c2);
            send_char(8'h0d); send_char(8'h0a);
            repeat (10) @(negedge clk);
        end
    endtask

    task expect_state(input [5:0] mask, value);
        begin
            if ((led & mask) !== value)
                $fatal(1, "LED mismatch: got=%b mask=%b expected=%b", led, mask, value);
        end
    endtask

    always @(posedge clk) begin
        if (diag_error) $fatal(1, "Diagnostic UART framing error");
        if (diag_valid) begin
            if (rx_pos == 0 && diag_byte != "D")
                $fatal(1, "Bad report start: byte=0x%02h", diag_byte);
            rx_line[rx_pos] = diag_byte;
            if (rx_pos == 7) begin
                if (rx_line[0] != "D" || rx_line[1] != "=" ||
                    rx_line[6] != 8'h0d || diag_byte != 8'h0a)
                    $fatal(1, "Bad report format");
                if (rx_line[2] == "0" && rx_line[3] == "2" &&
                    rx_line[4] == "0" && rx_line[5] == "0") saw_0200 = 1;
                if (rx_line[2] == "0" && rx_line[3] == "0" &&
                    rx_line[4] == "0" && rx_line[5] == "0") saw_0000 = 1;
                rx_pos = 0;
            end else rx_pos = rx_pos + 1;
        end
    end

    initial begin
        if ($bits(dut.heartbeat_count) < $clog2(50_000_000/2 + 1))
            $fatal(1, "Heartbeat counter too narrow for production clock");
        repeat (10) @(negedge clk);
        rst_n = 1;
        repeat (20) @(negedge clk);
        expect_state(6'b011110, 6'b010000); // No data: LED4 only.
        send_distance("9", "0", "0");
        expect_state(6'b011110, 6'b000010); // Valid, no slowing.
        send_distance("7", "0", "0");
        expect_state(6'b011110, 6'b001010); // Decelerate.
        send_distance("2", "0", "0");
        expect_state(6'b011110, 6'b000110); // Hard stop.
        repeat (12000) @(negedge clk);
        if (!saw_0200) $fatal(1, "Missing D=0200 report");
        repeat (45000) @(negedge clk);
        expect_state(6'b011110, 6'b010000); // Timeout clears stale distance.
        repeat (12000) @(negedge clk);
        if (!saw_0000) $fatal(1, "Missing D=0000 stale report");
        if (led[0] !== 1'b1) $fatal(1, "Heartbeat did not toggle");
        $display("TOF_SINGLE_BRINGUP_PASS");
        $finish;
    end
endmodule
