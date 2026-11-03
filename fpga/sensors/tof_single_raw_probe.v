// Temporary raw UART probe: forward ToF TXD to the board USB-UART TX.
// This is for checking the module's real output mode, not motor control.
module tof_single_raw_probe #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer TOF_BAUD = 115200,
    parameter integer DIAG_BAUD = 115200
) (
    input wire clk_50m_i,
    input wire key_s0_n_i,
    input wire tof_uart_rx_i,
    output wire diag_uart_tx_o,
    output wire [5:0] led_o
);
    wire unused_formatted_tx;
    tof_single_bringup #(.CLK_HZ(CLK_HZ), .TOF_BAUD(TOF_BAUD),
                         .DIAG_BAUD(DIAG_BAUD)) u_status (
        .clk_50m_i(clk_50m_i), .key_s0_n_i(key_s0_n_i),
        .tof_uart_rx_i(tof_uart_rx_i),
        .diag_uart_tx_o(unused_formatted_tx), .led_o(led_o)
    );
    // Both interfaces are 3.3 V UART. Pass through the raw line so XCOM can
    // show ASCII or HEX and identify a non-default ToF configuration.
    assign diag_uart_tx_o = tof_uart_rx_i;
endmodule
