if {[file exists sim_motor_encoder_decimal]} {vdel -lib sim_motor_encoder_decimal -all}
vlib sim_motor_encoder_decimal
vmap sim_motor_encoder_decimal sim_motor_encoder_decimal
vlog -work sim_motor_encoder_decimal ../encoder_speed.v ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v ../motor_m1_bringup/acg720_motor_m1_kick_80.v seg7_hc595_scan.v acg720_motor_encoder_decimal.v
vlog -sv -work sim_motor_encoder_decimal tb_acg720_motor_encoder_decimal.sv tb_seg7_hc595_scan.sv
vsim -c -voptargs=+acc sim_motor_encoder_decimal.tb_acg720_motor_encoder_decimal
run -all
quit -sim
