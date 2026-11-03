`timescale 1ns/1ps
module tb_sin12_r20_tof_band_equivalence;
reg[15:0] distance=0;reg valid=0;wire stop;wire[9:0] scale;
reg[15:0] target=0;wire[15:0] old_target=stop?0:scale>=1000?target:scale>=750?target-(target>>2):(target>>1);
wire[15:0] new_target=stop?0:distance>=800?target:distance>=500?target-(target>>2):(target>>1);
wire[1:0] old_band=stop?0:scale>=1000?3:scale>=750?2:1;
wire[1:0] new_band=stop?0:distance>=800?3:distance>=500?2:1;
tof_obstacle_guard #(.HARD_STOP_MM(100)) original(.d0_i(distance),.d1_i(16'd0),.d2_i(16'd0),.d3_i(16'd0),.valid_i({3'd0,valid}),.valid_o(),.obstacle_o(),.hard_stop_o(stop),.decel_o(),.speed_scale_permille_o(scale),.nearest_mm_o());
integer v,d,t,cases=0;
initial begin
 for(v=0;v<2;v=v+1)for(d=0;d<65536;d=d+1)begin
  valid=v;distance=d;target=(d*3137)^16'hA55A;#1;
  if(old_band!==new_band ||old_target!==new_target)$fatal(1,"band mismatch valid%0d dist%0d scale%0d",v,d,scale);
  cases=cases+1;
 end
 for(d=0;d<1000;d=d+1)for(t=0;t<16;t=t+1)begin
  valid=1;distance=d;target=t==15?65535:t==14?32768:(1<<t)-1;#1;
  if(old_target!==new_target)$fatal(1,"full-word data mismatch dist%0d target%0d",d,target);
 end
 $display("R20_SINGLE_TOF_BAND_TWO_STATE_EQUIVALENCE_PASS cases=%0d data_vectors16000 no_latency_change",cases);$finish;
end
endmodule
