if {[file exists sim_motor_encoder_rate]} {vdel -lib sim_motor_encoder_rate -all}
vlib sim_motor_encoder_rate
vmap sim_motor_encoder_rate sim_motor_encoder_rate
vlog -work sim_motor_encoder_rate ../encoder_speed.v ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v ../motor_m1_bringup/acg720_motor_m1_kick_80.v acg720_motor_encoder_rate.v
vlog -sv -work sim_motor_encoder_rate tb_acg720_motor_encoder_rate.sv
vsim -c -voptargs=+acc sim_motor_encoder_rate.tb_acg720_motor_encoder_rate
run -all
quit -sim
