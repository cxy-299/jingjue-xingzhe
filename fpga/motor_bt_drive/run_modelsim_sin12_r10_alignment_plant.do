onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r10_alignment_plant]} {vlib sim_sin12_r10_alignment_plant}
vlog -work sim_sin12_r10_alignment_plant chassis_trim.v vision_mission_guard.v
vlog -sv -work sim_sin12_r10_alignment_plant tb_sin12_r10_alignment_plant.sv
vsim -c sim_sin12_r10_alignment_plant.tb_sin12_r10_alignment_plant
run -all
quit -f
