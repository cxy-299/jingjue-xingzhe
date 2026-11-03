// Pixel-rate TMDS encoding and native 10:1 Arora V IOLOGIC serialization.
// UG304 4.3.5: PCLK=FCLK/5, D0 first, active-high asynchronous RESET.
// One OSER10 consumes the pair's IOLOGIC. UG304 3.6.6 ELVDS_OBUF
// produces complementary outputs using the two LVCMOS buffers, without a
// second serializer or fabric inverter. CST uses LVCMOS33D, 3.3 V, 8 mA;
// preserve the ACG720 HDMI2 pinout and its 49.9-ohm pull-ups (sheet 8).
module dvi_encoder #(parameter integer SEPARATE_RESET=0)(
 input wire pixelclk,pixelclk5x,rst_n,serializer_reset_i,
 input wire[7:0] blue_din,green_din,red_din,
 input wire hsync,vsync,de,
 output wire tmds_clk_p,tmds_clk_n,
 output wire[2:0] tmds_data_p,tmds_data_n
);
 wire[9:0] blue,green,red;
 encode encb(.clk(pixelclk),.rst_n(rst_n),.din(blue_din),.c0(hsync),.c1(vsync),.de(de),.dout(blue));
 encode encg(.clk(pixelclk),.rst_n(rst_n),.din(green_din),.c0(1'b0),.c1(1'b0),.de(de),.dout(green));
 encode encr(.clk(pixelclk),.rst_n(rst_n),.din(red_din),.c0(1'b0),.c1(1'b0),.de(de),.dout(red));
 wire[39:0] words={10'b1111100000,red,green,blue};
 wire[3:0] pins_p,pins_n;
 genvar channel;
 generate for(channel=0;channel<4;channel=channel+1)begin:g_channel
  sin12_oser10_pair u_serial(.pclk(pixelclk),.fclk(pixelclk5x),.reset(SEPARATE_RESET ? serializer_reset_i:~rst_n),
   .data(words[channel*10+:10]),.q_p(pins_p[channel]),.q_n(pins_n[channel]));
 end endgenerate
 assign tmds_data_p=pins_p[2:0];assign tmds_data_n=pins_n[2:0];
 assign tmds_clk_p=pins_p[3];assign tmds_clk_n=pins_n[3];
endmodule

module sin12_oser10_pair(
 input wire pclk,fclk,reset,input wire[9:0]data,
 output wire q_p,q_n
);
 // sin12_video_startup releases RESET at least 160 ns before enabling FCLK.
 // Keep this primitive free of fabric FCLK registers (different clock trees).
 wire serial;
 OSER10 u_serializer(.Q(serial),.D0(data[0]),.D1(data[1]),.D2(data[2]),.D3(data[3]),.D4(data[4]),
  .D5(data[5]),.D6(data[6]),.D7(data[7]),.D8(data[8]),.D9(data[9]),.PCLK(pclk),.FCLK(fclk),.RESET(reset));
 ELVDS_OBUF u_output_pair(.I(serial),.O(q_p),.OB(q_n));
endmodule
