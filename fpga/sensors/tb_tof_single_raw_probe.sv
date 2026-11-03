`timescale 1ns/1ps
module tb_tof_single_raw_probe;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg tof_rx = 1;
    wire diag_tx;
    wire [5:0] led;
    tof_single_raw_probe #(.CLK_HZ(100_000), .TOF_BAUD(10_000),
                           .DIAG_BAUD(10_000)) dut (
        .clk_50m_i(clk), .key_s0_n_i(rst_n), .tof_uart_rx_i(tof_rx),
        .diag_uart_tx_o(diag_tx), .led_o(led)
    );
    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        if (diag_tx !== 1'b1) $fatal(1, "Idle state not high");
        tof_rx = 0;
        #1;
        if (diag_tx !== 1'b0) $fatal(1, "Raw low not forwarded");
        tof_rx = 1;
        #1;
        if (diag_tx !== 1'b1) $fatal(1, "Raw high not forwarded");
        $display("TOF_RAW_PROBE_PASS");
        $finish;
    end
endmodule
