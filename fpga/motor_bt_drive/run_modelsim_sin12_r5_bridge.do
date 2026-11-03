onerror {quit -code 1 -f}
if {![file exists sim_sin12_r5_bridge]} {vlib sim_sin12_r5_bridge}
vlog -work sim_sin12_r5_bridge manual_avoid_bridge.v
vlog -sv -work sim_sin12_r5_bridge tb_sin12_r5_bridge.sv
vsim -c sim_sin12_r5_bridge.tb_sin12_r5_bridge
run -all
quit -f
