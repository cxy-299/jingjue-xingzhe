onerror {quit -code 1 -f}
if {![file exists sim_sin12_r11_legacy_motor_mission]} {vlib sim_sin12_r11_legacy_motor_mission}
vlog -work sim_sin12_r11_legacy_motor_mission heading_approach_control.v ../encoder_speed.v ../motor_pwm_dir.v ../uart_rx.v ../nav/nav_path_parser.v ../bluetooth_bringup/uart_tx_echo.v ../motor_four_closed_loop/acg720_motor_four_closed_loop.v bt_motion_guard.v motor_four_diag_uart.v bt_combined_diag_uart.v ../nav/nav_route_executor.v ../sensors/imu_yahboom_uart.v ../sensors/tof_ms53l2m_ascii_uart.v ../sensors/tof_obstacle_guard.v ../sensors/sensor_task1_3_core.v ../sensors/sensor_status_uart.v ../vision_packet_parser.v vision_follow_guard.v chassis_trim.v bt_pid_config.v motor_recovery_guard.v manual_avoid_bridge.v acg720_motor_bt_drive.v yaw_float_to_q13.v bt_turn_packet_rx.v imu_turn_guard.v bt_mission_packet_rx.v vision_mission_guard.v bt_autonav_packet_rx.v ../nav/nav_unsigned_divider.v ../nav/grid_bfs_dynamic.v ../nav/autonomous_nav_guard.v acg720_motor_bt_autonav.v
vlog -sv -work sim_sin12_r11_legacy_motor_mission tb_sin12_r5_mission.sv
vsim -c sim_sin12_r11_legacy_motor_mission.tb_sin12_r5_mission
run -all
quit -f

