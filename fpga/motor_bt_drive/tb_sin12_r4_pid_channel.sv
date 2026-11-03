`timescale 1ns/1ps
module tb_sin12_r4_pid_channel;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=0,tick=0;reg signed[16:0] speed=0;reg[5:0] p=8,i=0,d=2;
 wire signed[15:0] duty;wire fault;
 motor_four_pi_channel #(.KICK_CYCLES(50),.KICK_RAMP_ENABLE(1),.RUNTIME_PID_ENABLE(1)) dut(
  .clk(clk),.rst_n(rst),.enable_i(en),.sample_tick_i(tick),.forward_speed_i(speed),.target_counts_i(16'sd20),
  .duty_o(duty),.fault_o(fault),.feedback_seen_o(),.fault_reason_o(),.fault_speed_o(),.fault_duty_o(),
  .kp_i(p),.ki_i(i),.kd_i(d),.feedback_start_i(1'b1));
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task sample;begin tick=1;clocks(1);tick=0;clocks(5);end endtask
 integer round_index,n,integral_model,error_model,previous_model,desired_model,duty_model,derivative_model;
 initial begin
  clocks(3);rst=1;en=1;speed=18;clocks(3);sample();
  if(duty!=616 || !dut.kick_active)$fatal(1,"spin feedback/default derivative start: %d",duty);
  speed=16;sample();if(duty!=636)$fatal(1,"runtime P/D effect wrong: %d",duty);
  en=0;clocks(3);p=4;i=1;d=0;en=1;clocks(3);speed=18;sample();
  if(duty!=610)$fatal(1,"runtime PI reset: %d",duty);
  en=0;clocks(2);if(duty || fault)$fatal(1,"stop changed protections");
  for(round_index=0;round_index<8;round_index=round_index+1)begin
   en=0;clocks(3);p=$urandom_range(0,32);i=$urandom_range(0,8);d=$urandom_range(0,32);
   en=1;speed=20;clocks(3);integral_model=0;previous_model=0;duty_model=600;
   for(n=0;n<20;n=n+1)begin
    speed=$urandom_range(0,40);error_model=20-speed;
    derivative_model=(n==0)?0:error_model-previous_model;previous_model=error_model;
    integral_model=integral_model+i*error_model;
    if(integral_model>120)integral_model=120;
    if(integral_model< -120)integral_model=-120;
    desired_model=600+p*error_model+integral_model+d*derivative_model;
    if(desired_model>850)desired_model=850;
    if(desired_model<300)desired_model=300;
    if(desired_model>duty_model+50)duty_model=duty_model+50;
    else if(desired_model<duty_model-50)duty_model=duty_model-50;
    else duty_model=desired_model;
    sample();
    if(duty!=duty_model || fault)$fatal(1,"PID model mismatch round%0d sample%0d got%0d expected%0d",round_index,n,duty,duty_model);
   end
  end
  $display("R4_RUNTIME_PID_DERIVATIVE_RESET_SPIN_FEEDBACK_RANDOM160_PASS");$finish;
 end
endmodule
