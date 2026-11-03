onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_visual_primary]} {vlib sim_visual_primary}
vlog -work sim_visual_primary visual_primary_approach.v vision_mission_guard.v ../vision_packet_parser.v
vlog -sv -work sim_visual_primary tb_visual_primary_approach.sv tb_visual_primary_parser.sv tb_visual_primary_mission.sv
if {![info exists testtop]} {set testtop tb_visual_primary_approach}
vsim -c sim_visual_primary.$testtop
run -all
quit -f

