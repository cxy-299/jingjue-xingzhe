onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r7_guard]} {vlib sim_sin12_r7_guard}
vlog -work sim_sin12_r7_guard imu_turn_guard.v
vlog -sv -work sim_sin12_r7_guard tb_sin12_r7_guard.sv
vsim -c sim_sin12_r7_guard.tb_sin12_r7_guard
run -all
quit -f
