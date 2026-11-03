onerror {quit -code 1 -f}
if {![file exists sim_sin12_direction]} {vlib sim_sin12_direction}
vlog -sv -work sim_sin12_direction ../encoder_speed.v chassis_trim.v bt_pid_config.v motor_recovery_guard.v manual_avoid_bridge.v acg720_motor_bt_drive.v tb_sin12_direction_filter.sv
vsim -c sim_sin12_direction.tb_sin12_direction_filter
run -all
quit -f

