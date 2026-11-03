if {![file exists sim_motor_three_forward]} {vlib sim_motor_three_forward}
vmap sim_motor_three_forward sim_motor_three_forward
vlog -work sim_motor_three_forward ../encoder_speed.v ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v ../bluetooth_bringup/uart_tx_echo.v ../motor_three_calibrate/acg720_motor_three_calibrate.v acg720_motor_three_forward.v
vlog -sv -work sim_motor_three_forward tb_acg720_motor_three_forward.sv
vsim -c -voptargs=+acc sim_motor_three_forward.tb_acg720_motor_three_forward
run -all
quit -sim
