`timescale 1ns/1ps
module tb_nav_route_executor_pipeline;
reg clk=0;always #10 clk=~clk;
reg rst_n=0,tick=0,load=0,cancel=0;
reg [7:0] steps=3;reg[127:0] bits=128'h24;
reg[31:0] p0=0,p1=0,p2=0,p3=0;
wire [1:0] active,advance,done,fault;wire[2:0] command[0:1];
genvar g;generate for(g=0;g<2;g=g+1)begin:d
nav_route_executor #(.CELL_COUNTS(10),.TURN_NEUTRAL_SAMPLES(2),.PROGRESS_PIPELINE(g)) dut(
.clk(clk),.rst_n(rst_n),.sample_tick_i(tick),.route_valid_i(load),.step_count_i(steps),.route_bits_i(bits),
.position0_i(p0),.position1_i(p1),.position2_i(p2),.position3_i(p3),.cancel_i(cancel),
.active_o(active[g]),.advance_o(advance[g]),.done_o(done[g]),.fault_o(fault[g]),.command_o(command[g]));
end endgenerate
integer n;reg[31:0] base;reg signed[31:0] move0,move1,move2,move3;
task settle;begin repeat(12)@(negedge clk);end endtask
task compare;begin
if(active[0]!==active[1] || advance[0]!==advance[1] || done[0]!==done[1] || fault[0]!==fault[1] || command[0]!==command[1])
 $fatal(1,"Direct/pipeline mismatch act=%b adv=%b done=%b fault=%b cmd=%d/%d",active,advance,done,fault,command[0],command[1]);
end endtask
task sample;begin settle;tick=1;@(negedge clk);compare;tick=0;end endtask
task request;begin @(negedge clk);load=1;@(negedge clk);load=0;compare;end endtask
task reset_all;begin @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;end endtask
initial begin
 reset_all;request;
 p0=-9;p1=9;p2=-9;p3=9;sample;if(active!==3 || advance!==0)$fatal(1,"Below threshold advanced");
 p0=-10;p1=10;p2=-10;p3=10;sample;if(advance!==3 || command[1]!==0)$fatal(1,"Threshold/turn neutral failed");
 // Pending old progress may not count a second cell during pipeline refill.
 @(negedge clk);tick=1;@(negedge clk);tick=0;if(advance[1])$fatal(1,"Old base progress double counted");
 // Both owners use the same two neutral samples; sample above consumed one.
 sample;if(command[1]!==2)$fatal(1,"Neutral transition failed");
 p0=-20;p1=20;p2=-20;p3=20;sample;sample;sample;
 p0=-30;p1=30;p2=-30;p3=30;sample;if(active!==0 || done!==3)$fatal(1,"Route did not finish");
 // Random signed displacement, including counter rollover and unequal wheels.
 for(n=0;n<400;n=n+1)begin
  steps=1;base=$random;p0=base;p1=base;p2=base;p3=base;request;
  move0=($random%25);move1=($random%25);move2=($random%25);move3=($random%25);
  p0=base+move0;p1=base+move1;p2=base+move2;p3=base+move3;sample;
 end
 p0=0;p1=0;p2=0;p3=0;request;p0=39;sample;
 if(advance!==0)$fatal(1,"Fractional average rounded up");
 p0=40;sample;if(done!==3)$fatal(1,"Average boundary failed");
 p0=0;p1=0;p2=0;p3=0;request;
 p0=32'h80000000;p1=p0;p2=p0;p3=p0;sample;
 if(done!==3)$fatal(1,"34-bit magnitude sum overflow");
 p0=32'hfffffffc;p1=p0;p2=p0;p3=p0;request;p0=6;p1=6;p2=6;p3=6;sample;
 if(active!==0 || done!==3)$fatal(1,"Counter wrap failed");
 // Replacement while old pipeline holds reached=1 must invalidate the old tag.
 steps=3;p0=0;p1=0;p2=0;p3=0;request;p0=30;p1=30;p2=30;p3=30;settle;
 request;@(negedge clk);tick=1;@(negedge clk);tick=0;
 if(advance[1] || !active[1])$fatal(1,"Replacement consumed old progress");
 settle;sample;if(advance[1])$fatal(1,"Stationary replacement advanced");
 // Cancel wins over route load and progress; removal never re-arms.
 p0=80;p1=80;p2=80;p3=80;settle;cancel=1;load=1;tick=1;
 @(negedge clk);compare;if(active!==0 || advance!==0)$fatal(1,"Cancel lost priority");
 cancel=0;load=0;tick=0;settle;sample;if(active!==0)$fatal(1,"Cancel restarted");
 steps=0;request;if(active!==0 || fault!==3)$fatal(1,"Zero route accepted");
 steps=65;request;if(active!==0 || fault!==3)$fatal(1,"Oversized route accepted");
 $display("R15_ROUTE_PIPELINE_SIGNED_WRAP_400_VECTORS_BASE_FLUSH_NEUTRAL_CANCEL_PASS");$finish;
end
initial begin #10000000;$fatal(1,"Route pipeline timeout");end
endmodule
