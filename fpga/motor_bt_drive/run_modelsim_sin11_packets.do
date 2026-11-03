onerror {quit -code 1 -f}
if {![file exists sim_sin11_packets]} {vlib sim_sin11_packets}
vlog -work sim_sin11_packets bt_mission_packet_rx.v bt_turn_packet_rx.v ../vision_packet_parser.v
vlog -sv -work sim_sin11_packets tb_sin11_packets.sv
vsim -c sim_sin11_packets.tb_sin11_packets
run -all
quit -f
