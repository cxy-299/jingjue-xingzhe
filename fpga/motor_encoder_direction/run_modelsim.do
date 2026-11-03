if {[file exists sim_motor_encoder_direction]} {vdel -lib sim_motor_encoder_direction -all}
vlib sim_motor_encoder_direction
vmap sim_motor_encoder_direction sim_motor_encoder_direction
vlog -work sim_motor_encoder_direction ../encoder_speed.v ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v ../motor_m1_bringup/acg720_motor_m1_kick_80.v acg720_motor_encoder_direction.v
vlog -sv -work sim_motor_encoder_direction tb_acg720_motor_encoder_direction.sv
vsim -c -voptargs=+acc sim_motor_encoder_direction.tb_acg720_motor_encoder_direction
run -all
quit -sim
