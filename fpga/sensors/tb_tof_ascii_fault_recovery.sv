`timescale 1ns/1ps
// Real 50 MHz / 115200 UART pins; no force of parser state or received bytes.
module tb_tof_ascii_fault_recovery;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    reg rx = 1;
    wire [15:0] distance;
    wire valid, error;
    integer accepted = 0, errors = 0, checks = 0;
`ifdef TOF_GATE
    GSR GSR(.GSRI(1'b1));
    // The full design does not expose the receiver's error pulse. Mapped
    // acceptance is checked on its actual valid/distance outputs only.
    localparam CHECK_ERROR_OUTPUT = 0;
`else
    localparam CHECK_ERROR_OUTPUT = 1;
`endif
    tof_ms53l2m_ascii_uart dut (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(rx),
        .distance_mm_o(distance), .valid_pulse_o(valid), .frame_error_o(error)
    );
    always @(negedge clk) begin
        if (rst_n && valid) accepted = accepted + 1;
        if (rst_n && error) errors = errors + 1;
    end

    task send_byte(input [7:0] value, input bit good_stop);
        begin
            @(negedge clk); rx = 0;
            repeat (434) @(negedge clk);
            for (integer k = 0; k < 8; k = k + 1) begin
                rx = value[k]; repeat (434) @(negedge clk);
            end
            rx = good_stop; repeat (434) @(negedge clk);
            rx = 1; repeat (434 * 3) @(negedge clk);
        end
    endtask
    task text(input string s);
        begin
            for (integer k = 0; k < s.len(); k = k + 1) send_byte(s[k], 1);
            repeat (20) @(negedge clk);
        end
    endtask
    task good(input string s, input integer expected_mm);
        integer n, e;
        begin
            n = accepted; e = errors; text(s);
            if (accepted != n + 1 || distance !== expected_mm || errors != e)
                $fatal(1, "Good line failed: expected=%0d got=%0d accepted=%0d errors=%0d", expected_mm, distance, accepted-n, errors-e);
            checks = checks + 1;
        end
    endtask
    task rejected(input string s);
        integer n, e; reg [15:0] old_distance;
        begin
            n = accepted; e = errors; old_distance = distance; text(s);
            if (accepted != n || distance !== old_distance || (CHECK_ERROR_OUTPUT && errors <= e))
                $fatal(1, "Bad line accepted or not reported: line=%s old=%0d got=%0d accepted=%0d", s, old_distance, distance, accepted-n);
            checks = checks + 1;
        end
    endtask
    task bad_byte_line(input string prefix, input [7:0] broken, input string suffix);
        integer n, e; reg [15:0] old_distance;
        begin
            n = accepted; e = errors; old_distance = distance;
            text(prefix); send_byte(broken, 0); text(suffix);
            if (accepted != n || distance !== old_distance || (CHECK_ERROR_OUTPUT && errors <= e))
                $fatal(1, "Framing-error line committed: prefix=%s got=%0d accepted=%0d", prefix, distance, accepted-n);
            checks = checks + 1;
        end
    endtask
    initial begin
        repeat (10) @(negedge clk); rst_n = 1;
        good("1707\r\n", 1707);
        rejected("4294968996\r\n"); // 2^32 + 1700 must not wrap to 1700.
        good("1708\n", 1708);
        rejected("4294967336\r\n"); // Wrapped value40 must not appear as a near obstacle.
        rejected("99999999999999999999999999999999999999999999999999\r\n");
        rejected("8001,1700\r\n");
        rejected("0\r\n"); rejected("39\n");
        good("40\r\n", 40); good("8000\n", 8000);
        good("000001700\r\n", 1700);
        good(" 1701\r\n", 1701);
        good("1702,987654321098765432109876543210\r\n", 1702);
        good("1703,3.21\n", 1703);
        bad_byte_line("17", "9", "00\r\n");
        good("1704\r\n", 1704);
        bad_byte_line("", "1", "700\r\n");
        good("1705\r\n", 1705);
        bad_byte_line("170", "0", "\r\n");
        good("1706\r\n", 1706);
        bad_byte_line("1700,", "3", ".21\r\n");
        good("1707\r\n", 1707);
        bad_byte_line("1700", 8'h0d, "\n");
        good("1708\r\n", 1708);
        // If LF itself is lost, discard through the next intact delimiter.
        bad_byte_line("", 8'h0a, "1700\r\n");
        good("1709\r\n", 1709);
        text("4294968996"); rst_n = 0;
        repeat (20) @(negedge clk); rst_n = 1;
        good("1710\r\n", 1710);
        for (integer k = 0; k < 64; k = k + 1)
            good($sformatf("%0d\r\n", 40 + (k * 127) % 7961), 40 + (k * 127) % 7961);
        $display("TOF_ASCII_FAULT_RECOVERY_PASS checks=%0d accepted=%0d", checks, accepted);
        $finish;
    end
    initial begin #200000000; $fatal(1, "Fault-recovery test timeout"); end
endmodule
