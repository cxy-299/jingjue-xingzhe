`timescale 1ns/1ps
module tb_sin12_direction_filter;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,request=0;reg[2:0] command=0;wire enabled;
 motor_direction_interlock #(.QUIET_CYCLES(10)) guard(
  .clk(clk),.rst_n(rst),.request_i(request),.command_i(command),.enable_o(enabled));
 reg a=0,b=0,tick=0;wire signed[31:0] position;wire signed[15:0] speed;
 encoder_speed #(.FILTER_CYCLES(5)) encoder(.clk(clk),.rst_n(rst),
  .encoder_a_i(a),.encoder_b_i(b),.sample_tick_i(tick),.position_o(position),.speed_o(speed));
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task step(input [1:0] ab);begin {a,b}=ab;clocks(12);end endtask
 initial begin
  clocks(3);rst=1;clocks(3);request=1;command=1;clocks(3);
  if(!enabled)$fatal(1,"first start blocked");
  command=2;#1;if(enabled)$fatal(1,"reverse PWM not removed immediately");
  clocks(5);if(enabled)$fatal(1,"neutral interval bypassed");
  clocks(9);if(!enabled)$fatal(1,"reverse did not restart");
  clocks(20);if(!enabled)$fatal(1,"same-command heartbeat restarted interlock");
  request=0;#1;if(enabled)$fatal(1,"fault shutdown delayed");
  clocks(2);command=1;request=1;clocks(2);
  if(enabled)$fatal(1,"brief stop bypassed reversal quiet time");
  clocks(12);if(!enabled)$fatal(1,"restart after neutral missing");
  // A 20ns input glitch crosses synchronizers but not the stable-pair filter.
  b=1;clocks(2);b=0;clocks(15);
  if(position!=0)$fatal(1,"short encoder pulse counted");
  step(1);step(3);step(2);step(0);
  if(position!=4)$fatal(1,"valid quadrature lost: %d",position);
  step(2);step(3);step(1);step(0);
  if(position!=0)$fatal(1,"reverse quadrature lost");
  $display("SIN12_DIRECTION_INTERLOCK_ENCODER_FILTER_PASS");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
