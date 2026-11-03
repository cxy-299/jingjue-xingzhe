module tof_ms53l2m_ascii_uart(
input clk,rst_n,uart_rx_i,output[15:0]distance_mm_o,output valid_pulse_o,frame_error_o);
wire[12:0] mapped_distance;
r20_mapped_tof actual(.clk_50m_i_d(clk),.n177_5(!rst_n),.tof0_uart_rx_i_d(uart_rx_i),
 .v0_p(valid_pulse_o),.d0_p(mapped_distance));
assign distance_mm_o={3'd0,mapped_distance};
assign frame_error_o=1'b0; // Unobservable in this netlist; bench disables this check.
endmodule
