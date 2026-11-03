onerror {quit -code 1 -f}
if {![file exists sim_start_stagger]} {vlib sim_start_stagger}
vmap sim_start_stagger sim_start_stagger
vlog -work sim_start_stagger ../encoder_speed.v ../motor_pwm_dir.v ../uart_rx.v ../bluetooth_bringup/uart_tx_echo.v ../motor_four_closed_loop/acg720_motor_four_closed_loop.v bt_motion_guard.v motor_four_diag_uart.v ../sensors/sensor_status_uart.v ../nav/nav_path_parser.v ../nav/nav_route_executor.v ../sensors/imu_yahboom_uart.v ../sensors/tof_ms53l2m_ascii_uart.v ../sensors/tof_obstacle_guard.v ../sensors/sensor_task1_3_core.v chassis_trim.v bt_pid_config.v motor_recovery_guard.v manual_avoid_bridge.v acg720_motor_bt_drive.v
vlog -work sim_start_stagger bt_combined_diag_uart.v
vlog -sv -work sim_start_stagger tb_start_stagger_125.sv
vsim -c -voptargs=+acc sim_start_stagger.tb_start_stagger_125
run -all
quit -f

