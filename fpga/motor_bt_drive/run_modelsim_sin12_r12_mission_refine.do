onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r12_refine]} {vlib sim_sin12_r12_refine}
vlog -work sim_sin12_r12_refine vision_mission_guard.v
vlog -sv -work sim_sin12_r12_refine tb_sin12_r12_mission_refine.sv
vsim -c sim_sin12_r12_refine.tb_sin12_r12_mission_refine
run -all
quit -f
