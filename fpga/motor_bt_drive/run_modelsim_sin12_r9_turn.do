onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r9_turn]} {vlib sim_sin12_r9_turn}
vlog -work sim_sin12_r9_turn heading_approach_control.v imu_turn_guard.v
vlog -sv -work sim_sin12_r9_turn tb_sin12_r9_turn.sv
vsim -c sim_sin12_r9_turn.tb_sin12_r9_turn
run -all
quit -f
