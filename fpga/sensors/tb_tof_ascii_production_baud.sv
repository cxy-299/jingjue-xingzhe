`timescale 1ns/1ps
module tb_tof_ascii_production_baud;
    localparam integer CLOCK_HZ = 50_000_000;
    localparam integer BAUD = 115200;
    localparam integer CLKS_PER_BIT = (CLOCK_HZ + BAUD/2) / BAUD;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    reg rx = 1;
    wire [15:0] distance;
    wire valid;
    wire error;
    integer valid_count = 0;
    tof_ms53l2m_ascii_uart #(.CLK_HZ(CLOCK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(rx),
        .distance_mm_o(distance), .valid_pulse_o(valid),
        .frame_error_o(error)
    );

    task send_byte(input [7:0] value);
        integer bit_no;
        begin
            rx = 0;
            repeat (CLKS_PER_BIT) @(negedge clk);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                rx = value[bit_no];
                repeat (CLKS_PER_BIT) @(negedge clk);
            end
            rx = 1;
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (error) $fatal(1, "UART or range error");
        if (valid) begin
            valid_count = valid_count + 1;
            if (distance != 16'd455 && distance != 16'd467)
                $fatal(1, "Unexpected distance %0d", distance);
        end
    end

    initial begin
        repeat (10) @(negedge clk);
        rst_n = 1;
        send_byte("4"); send_byte("5"); send_byte("5");
        send_byte(8'h0d); send_byte(8'h0a);
        send_byte("4"); send_byte("6"); send_byte("7");
        send_byte(8'h0d); send_byte(8'h0a);
        repeat (10) @(negedge clk);
        if (valid_count != 2 || distance != 16'd467)
            $fatal(1, "Expected two valid frames ending in 467; count=%0d distance=%0d", valid_count, distance);
        $display("TOF_ASCII_PRODUCTION_BAUD_PASS");
        $finish;
    end
endmodule
