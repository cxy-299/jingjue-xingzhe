`timescale 1ns/1ps
// Clock/serializer/SCCB stubs exercise frame ownership, not analogue IO timing.
module camera_pll(input clkin,mdclk,reset,output clkout0,clkout1,clkout2,lock);
 assign clkout0=clkin;assign clkout1=clkin;assign clkout2=clkin;assign lock=~reset;
endmodule
module CLKDIV(input RESETN,HCLKIN,CALIB,output CLKOUT);
 parameter DIV_MODE="5";assign CLKOUT=HCLKIN;
endmodule
// Frame-ownership test only; native DHCE timing is verified separately.
module DHCE(input CLKIN,CEN,output CLKOUT);
 assign CLKOUT=CLKIN && !CEN;
endmodule
module camera_init #(parameter SYS_CLOCK=0,SCL_CLOCK=0,CAMERA_TYPE="ov5640",IMAGE_TYPE=0,
 IMAGE_WIDTH=1280,IMAGE_HEIGHT=720,IMAGE_FLIP_EN=0,IMAGE_MIRROR_EN=0)(
 input Clk,Rst_n,output Init_Done,camera_rst_n,camera_pwdn,i2c_sclk,inout i2c_sdat);
 assign Init_Done=Rst_n;assign camera_rst_n=Rst_n;assign camera_pwdn=0;assign i2c_sclk=0;
endmodule
module dvi_encoder #(parameter SEPARATE_RESET=0)(input pixelclk,pixelclk5x,rst_n,serializer_reset_i,input[7:0]blue_din,green_din,red_din,
 input hsync,vsync,de,output tmds_clk_p,tmds_clk_n,output[2:0]tmds_data_p,tmds_data_n);
 assign tmds_clk_p=pixelclk;assign tmds_clk_n=~pixelclk;
 assign tmds_data_p=0;assign tmds_data_n=0;
endmodule
module tb_camera_framebuffer;
 reg sysclk=0;always #5 sysclk=~sysclk;
 reg camclk=0;always #3 camclk=~camclk;
 reg rst=0,vs=0,href=0;reg[7:0]data=0;wire valid;
 sin12_camera_hdmi dut(.clk50M(sysclk),.reset_n(rst),.camera_vsync(vs),.camera_href(href),
 .camera_pclk(camclk),.camera_data(data),.camera_sclk(),.camera_xclk(),.camera_rst_n(),
 .camera_pwdn(),.camera_sdat(),.tmds_clk_p(),.tmds_clk_n(),.tmds_data_p(),.tmds_data_n(),
 .init_done_o(),.frame_valid_o(valid));
 task clocks(input integer n);repeat(n)@(negedge camclk);endtask
 task frame(input[15:0]color);
  integer row,col;
  begin
   vs=1;href=0;clocks(12);vs=0;clocks(4);
   for(row=0;row<720;row=row+1)begin
    href=1;
    for(col=0;col<1280;col=col+1)begin data=color[15:8];clocks(1);data=color[7:0];clocks(1);end
    href=0;clocks(4);
   end
   vs=1;clocks(12);vs=0;
  end
 endtask
 integer first_bank,base;
 integer pixel_release_edges=0;
 always @(negedge dut.video_reset_n)pixel_release_edges=0;
 always @(posedge dut.pixel_clk)begin
  if(!dut.video_reset_n)pixel_release_edges=0;
  else pixel_release_edges=pixel_release_edges+1;
  #1;
  if(pixel_release_edges<2 && dut.pixel_reset_n)$fatal(1,"pixel reset released before two edges");
 end
 function[8:0] rgb333(input[15:0]c);rgb333={c[15:13],c[10:8],c[4:2]};endfunction
 initial begin
  clocks(10);rst=1;clocks(80);
  frame(16'h1234);wait(valid);clocks(10);
  first_bank=dut.front_bank;base=first_bank*57600;
  if(dut.memory[base]!==rgb333(16'h1234) || dut.memory[base+57599]!==rgb333(16'h1234))
   $fatal(1,"first frame pixels/coordinates incorrect");
  wait(!dut.pending);clocks(20);
  frame(16'hcafe);
  if(dut.memory[base]!==rgb333(16'h1234))$fatal(1,"producer overwrote displayed bank");
  wait(dut.front_bank!=first_bank);clocks(10);base=dut.front_bank*57600;
  if(dut.memory[base]!==rgb333(16'hcafe) || dut.memory[base+57599]!==rgb333(16'hcafe))
   $fatal(1,"second frame handoff incorrect");
  rst=0;#1;
  if(dut.pixel_reset_n || dut.h || dut.v || valid)$fatal(1,"pixel async reset assertion failed");
  clocks(10);rst=1;clocks(80);
  if(!dut.pixel_reset_n || valid)$fatal(1,"pixel restart reused prior frame");
  $display("SIN12_PIXEL_RESET_ASYNC_ASSERT_TWO_EDGE_RELEASE_RESTART_PASS");
  $display("SIN12_CAMERA_DOUBLE_BUFFER_CDC_FRAME_HANDOFF_PASS");$finish;
 end
 initial begin #80000000;$fatal(1,"framebuffer timeout");end
endmodule
