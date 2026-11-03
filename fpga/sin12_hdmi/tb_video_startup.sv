`timescale 1ps/1ps
module tb_video_startup;
 reg sysclk=0;always #10000 sysclk=~sysclk;
 reg rawclk=0;always #1333 rawclk=~rawclk;
 reg rst_n=0,locked=0,gsr_n=0;
 wire fclk,srst,ready,pclk,qp,qn;
 GSR GSR(.GSRI(gsr_n));
 sin12_video_startup dut(.sys_clk(sysclk),.source_serial_clk(rawclk),
  .reset_n(rst_n),.pll_locked(locked),.serial_clk(fclk),.serializer_reset(srst),.ready(ready));
 CLKDIV u_div(.RESETN(~srst),.HCLKIN(fclk),.CLKOUT(pclk),.CALIB(1'b1));
 defparam u_div.DIV_MODE="5";
 sin12_oser10_pair u_pair(.pclk(pclk),.fclk(fclk),.reset(srst),.data(10'h12d),.q_p(qp),.q_n(qn));
 time released_at=0,asserted_at=0,rise_at=0;
 integer edges=0;
 always @(negedge srst)released_at=$time;
 always @(posedge srst)asserted_at=$time;
 always @(posedge fclk)begin
  if(!gsr_n)$fatal(1,"FCLK started during global reset");
  if(srst)begin
   if($time-asserted_at>12000)$fatal(1,"DHCE failed to drain/stop after reset");
  end else begin
   if(!ready)$fatal(1,"FCLK started before ready");
   if($time-released_at<160000)$fatal(1,"reset quiet window shorter than 160 ns");
  end
  rise_at=$time;edges=edges+1;
 end
 always @(negedge fclk)if(edges>0 && $time-rise_at!=1333)
  $fatal(1,"DHCE produced a truncated high pulse");
 task start_and_check;
  integer before_edges,k,j,offset;reg[39:0]bits_seen;reg matched,one_match;
  begin
   before_edges=edges;rst_n=1;locked=1;
   wait(!srst);
   #150000;if(edges!=before_edges)$fatal(1,"clock edge during reset quiet window");
   wait(ready);repeat(20)@(posedge pclk);
   for(k=0;k<40;k=k+1)begin
    @(posedge fclk or negedge fclk);#5;
    if(qp!==~qn)$fatal(1,"non-complementary pair after gated startup");
    bits_seen[k]=qp;
   end
   matched=0;
   for(offset=0;offset<10;offset=offset+1)begin
    one_match=1;
    for(j=0;j<40;j=j+1)if(bits_seen[j]!==((10'h12d>>((j+offset)%10))&1))one_match=0;
    if(one_match)matched=1;
   end
   if(!matched)$fatal(1,"CLKDIV/OSER10 words failed after gated startup: %h",bits_seen);
  end
 endtask
 initial begin
  #20000;gsr_n=1;#40000;start_and_check();
  // Test asynchronous lock loss between raw clock edges. DHCE drains four
  // falling edges; RESET asserts immediately and then all clocks stop.
  #211;locked=0;#1;if(!srst)$fatal(1,"lock loss failed to assert RESET");
  #20000;rst_n=0;#40000;
  // The edge monitor permits only the documented four-edge DHCE drain.
  start_and_check();
  $display("SIN12_HDMI_QUIET_CLOCK_RESET_GUARD_PASS");$finish;
 end
 initial begin #3000000;$fatal(1,"startup sequencing timeout");end
endmodule
