if {![file exists sim_motor_four_closed_loop]} {vlib sim_motor_four_closed_loop}
vmap sim_motor_four_closed_loop sim_motor_four_closed_loop
vlog -work sim_motor_four_closed_loop ../encoder_speed.v ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v ../bluetooth_bringup/uart_tx_echo.v acg720_motor_four_closed_loop.v
vlog -sv -work sim_motor_four_closed_loop tb_acg720_motor_four_closed_loop.sv
vsim -c -voptargs=+acc sim_motor_four_closed_loop.tb_acg720_motor_four_closed_loop
run -all
quit -sim
