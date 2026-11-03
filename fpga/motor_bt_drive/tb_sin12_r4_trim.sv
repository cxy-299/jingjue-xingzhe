`timescale 1ns/1ps
module tb_sin12_r4_trim;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,tick=0,en=0,valid=1;reg[2:0] cmd=0,owner=0;
 reg signed[15:0] yaw=0,s0=0,s1=0,s2=0,s3=0;reg[15:0] base=20;
 wire[63:0] targets;wire locked;wire signed[15:0] reference_yaw,error_yaw;wire signed[7:0] correction;
 chassis_trim dut(clk,rst,tick,en,valid,cmd,owner,yaw,base,s0,s1,s2,s3,targets,locked,reference_yaw,error_yaw,correction);
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task sample;begin tick=1;clocks(1);tick=0;clocks(3);end endtask
 task check_targets(input integer a,b,c,d);
  if(targets!=={16'(d),16'(c),16'(b),16'(a)})$fatal(1,"targets %h != %d %d %d %d",targets,a,b,c,d);
 endtask
 initial begin
  clocks(3);rst=1;cmd=1;en=1;yaw=10000;clocks(5);
  if(!locked || reference_yaw!=10000)$fatal(1,"relative heading not captured");
  yaw=11000;sample();check_targets(23,17,23,17); // drift left -> clockwise correction
  en=0;clocks(3);check_targets(0,0,0,0);
  cmd=2;en=1;yaw=10000;clocks(5);yaw=11000;sample();check_targets(17,23,17,23);
  // A new owner must acquire its own reference, not inherit the manual target.
  owner=2;yaw=5000;clocks(5);if(reference_yaw!=5000)$fatal(1,"owner reference stale");
  en=0;clocks(3);cmd=1;yaw=25500;en=1;clocks(5);yaw=-25500;sample();
  if(error_yaw>=0 || error_yaw< -1000)$fatal(1,"yaw wrap wrong %d",error_yaw);
  valid=0;clocks(2);if(locked || correction)$fatal(1,"invalid IMU retained heading trim");
  valid=1;en=0;clocks(3);cmd=5;en=1;s0=8;s1=12;s2=8;s3=12;clocks(4);sample();
  // CCW left wheels reverse; speed imbalance gives positive forward drift.
  check_targets(21,19,21,19);
  en=0;clocks(3);cmd=6;en=1;s0=12;s1=8;s2=12;s3=8;clocks(4);sample();
  check_targets(19,21,19,21);
  // Equal requested rotation velocities give no translation trim.
  en=0;clocks(3);s0=10;s1=10;s2=10;s3=10;en=1;clocks(3);sample();check_targets(20,20,20,20);
  base=0;clocks(1);check_targets(0,0,0,0);
  $display("R4_HEADING_FORWARD_REVERSE_WRAP_OWNER_SPIN_TRANSLATION_PASS");$finish;
 end
endmodule
