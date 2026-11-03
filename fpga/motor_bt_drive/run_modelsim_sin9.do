onerror {quit -code 1 -f}
if {![file exists sim_sin9]} {vlib sim_sin9}
vlog -work sim_sin9 ../uart_rx.v ../vision_packet_parser.v vision_follow_guard.v
vlog -sv -work sim_sin9 tb_sin9_target_follow.sv
vsim -c sim_sin9.tb_sin9_target_follow
run -all
quit -f
