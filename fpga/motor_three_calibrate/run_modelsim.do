if {![file exists sim_motor_three_calibrate]} {vlib sim_motor_three_calibrate}
vmap sim_motor_three_calibrate sim_motor_three_calibrate
vlog -work sim_motor_three_calibrate ../encoder_speed.v ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v ../bluetooth_bringup/uart_tx_echo.v acg720_motor_three_calibrate.v
vlog -sv -work sim_motor_three_calibrate tb_acg720_motor_three_calibrate.sv
vsim -c -voptargs=+acc sim_motor_three_calibrate.tb_acg720_motor_three_calibrate
run -all
quit -sim
