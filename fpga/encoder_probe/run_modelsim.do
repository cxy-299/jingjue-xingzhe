if {![file isdirectory sim_encoder_probe]} {vlib sim_encoder_probe}
vlog -work sim_encoder_probe ../encoder_speed.v acg720_encoder_probe.v
vlog -sv -work sim_encoder_probe tb_acg720_encoder_probe.sv
vsim -c -voptargs=+acc sim_encoder_probe.tb_acg720_encoder_probe
run -all
quit -f
