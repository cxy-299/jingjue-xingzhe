if {![file exists sim_motor_bt_drive]} {vlib sim_motor_bt_drive}
vmap sim_motor_bt_drive sim_motor_bt_drive
vlog -work sim_motor_bt_drive ../encoder_speed.v ../motor_pwm_dir.v ../uart_rx.v ../bluetooth_bringup/uart_tx_echo.v ../motor_four_closed_loop/acg720_motor_four_closed_loop.v bt_motion_guard.v motor_four_diag_uart.v ../sensors/sensor_status_uart.v chassis_trim.v bt_pid_config.v motor_recovery_guard.v manual_avoid_bridge.v acg720_motor_bt_drive.v
vlog -sv -work sim_motor_bt_drive tb_acg720_motor_bt_drive.sv
vsim -c -voptargs=+acc sim_motor_bt_drive.tb_acg720_motor_bt_drive
run -all
quit -sim

