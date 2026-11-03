`timescale 1ps/1ps
module tb_native_tmds;
 reg fclk=0;always #1333 fclk=~fclk;
 reg pclk=0;always #6665 pclk=~pclk;
 reg reset=1;reg[9:0]data=10'h12d;
 wire qp,qn;
 GSR GSR(.GSRI(1'b1));
 sin12_oser10_pair dut(.pclk(pclk),.fclk(fclk),.reset(reset),.data(data),.q_p(qp),.q_n(qn));
 reg pixel_rst_n=0,separate_serial_reset=1;
 dvi_encoder #(.SEPARATE_RESET(1)) split(.pixelclk(pclk),.pixelclk5x(fclk),
  .rst_n(pixel_rst_n),.serializer_reset_i(separate_serial_reset),
  .blue_din(8'd0),.green_din(8'd0),.red_din(8'd0),.hsync(1'b0),.vsync(1'b0),.de(1'b0),
  .tmds_clk_p(),.tmds_clk_n(),.tmds_data_p(),.tmds_data_n());
 integer edges=0,phase=-1,k,j;reg[39:0]captured;reg match;
 always @(posedge fclk or negedge fclk)edges=edges+1;
 task check_word(input[9:0]word);
  integer base,offset,selected;
  begin
   @(negedge pclk);data=word;
   repeat(15)@(negedge pclk);
   for(k=0;k<40;k=k+1)begin
    @(posedge fclk or negedge fclk);#5;
    if(qp!==~qn)$fatal(1,"non-complementary TMDS outputs");
    if(k==0)base=edges;
    captured[k]=qp;
   end
   selected=-1;
   for(offset=0;offset<10;offset=offset+1)begin
    match=1;
    for(j=0;j<40;j=j+1)if(captured[j]!==word[(base+j+offset)%10])match=0;
    if(match)selected=offset;
   end
   if(selected<0)$fatal(1,"serializer word or LSB-first bit order incorrect word=%h got=%h",word,captured);
   if(phase<0)phase=selected;
   else if(selected!=phase)$fatal(1,"serializer changed word phase");
  end
 endtask
 integer bit_index;
 initial begin
  #10;separate_serial_reset=0;#10;
  if(split.g_channel[0].u_serial.reset!==0)$fatal(1,"pixel reset leaked into serializer RESET");
  pixel_rst_n=1;#10;pixel_rst_n=0;#10;
  if(split.g_channel[3].u_serial.reset!==0)$fatal(1,"pixel assertion changed gated-clock serializer reset");
  separate_serial_reset=1;#10;
  if(split.g_channel[3].u_serial.reset!==1)$fatal(1,"startup reset not propagated to serializer");
  repeat(5)@(negedge pclk);reset=0;
  check_word(10'h12d);
  for(bit_index=0;bit_index<10;bit_index=bit_index+1)check_word(10'b1<<bit_index);
  check_word(10'b1111100000);check_word(10'b1101010100);
  $display("SIN12_NATIVE_OSER10_LSB_FIRST_COMPLEMENT_PHASE_PASS");$finish;
 end
 initial begin #10000000;$fatal(1,"native serializer timeout");end
endmodule
