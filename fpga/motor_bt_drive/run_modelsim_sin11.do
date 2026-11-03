onerror {quit -code 1 -f}
if {![file exists sim_sin11]} {vlib sim_sin11}
vlog -work sim_sin11 vision_mission_guard.v bt_mission_packet_rx.v ../vision_packet_parser.v
vlog -sv -work sim_sin11 tb_sin11_mission.sv
vsim -c sim_sin11.tb_sin11_mission
run -all
quit -f
