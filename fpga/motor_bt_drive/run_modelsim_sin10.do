onerror {quit -code 1 -f}
if {![file exists sim_sin10]} {vlib sim_sin10}
vlog -work sim_sin10 yaw_float_to_q13.v bt_turn_packet_rx.v imu_turn_guard.v
vlog -sv -work sim_sin10 tb_sin10_heading.sv
vsim -c sim_sin10.tb_sin10_heading
run -all
quit -f
