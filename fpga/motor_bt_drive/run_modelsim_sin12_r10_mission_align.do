onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r10_mission_align]} {vlib sim_sin12_r10_mission_align}
vlog -work sim_sin12_r10_mission_align vision_mission_guard.v
vlog -sv -work sim_sin12_r10_mission_align tb_sin12_r10_mission_align.sv
vsim -c sim_sin12_r10_mission_align.tb_sin12_r10_mission_align
run -all
quit -f
