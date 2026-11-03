// UG306 4.1: native DHCE, CEN active low, safe HCLK stop/start.
// Release the serializer/CLKDIV reset while their clock is stopped, then
// wait eight complete 50 MHz cycles (160 ns) before enabling the HCLK.
// This is a functional quiet-clock interval, not a slower operating clock.
module sin12_video_startup(
 input wire sys_clk,source_serial_clk,reset_n,pll_locked,
 output wire serial_clk,serializer_reset,ready
);
 reg[4:0] wait_count=0;
 (* syn_preserve=1, syn_keep=1 *) reg reset_hold=1;
 reg clock_enable=0;
 wire startup_reset=~(reset_n && pll_locked);
 always @(posedge sys_clk or posedge startup_reset)begin
  if(startup_reset)begin
   wait_count<=0;reset_hold<=1;clock_enable<=0;
  end else begin
   if(wait_count<16)wait_count<=wait_count+1'b1;
   if(wait_count==7)reset_hold<=0;
   if(wait_count==15)clock_enable<=1;
  end
 end
 DHCE u_serial_gate(.CLKIN(source_serial_clk),.CEN(~clock_enable),.CLKOUT(serial_clk));
 assign serializer_reset=reset_hold;
 assign ready=clock_enable;
endmodule
