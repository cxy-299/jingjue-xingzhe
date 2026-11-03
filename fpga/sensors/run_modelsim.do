transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -sv ../uart_rx.v imu_yahboom_uart.v tof_ms53l2m_ascii_uart.v tof_obstacle_guard.v sensor_task1_3_core.v tb_sensor_frontend.sv
vsim -c work.tb_sensor_frontend
run -all
quit -f
