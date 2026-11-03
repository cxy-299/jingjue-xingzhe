onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_r10_legacy_mission]} {vlib sim_r10_legacy_mission}
vlog -work sim_r10_legacy_mission vision_mission_guard.v
vlog -sv -work sim_r10_legacy_mission tb_sin11_mission.sv
vsim -c sim_r10_legacy_mission.tb_sin11_mission
run -all
quit -f
