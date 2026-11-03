onerror {quit -code 1 -f}
if {![file exists sim_sin12_unit]} {vlib sim_sin12_unit}
vlog -work sim_sin12_unit ../nav/nav_unsigned_divider.v ../nav/grid_bfs_dynamic.v ../nav/autonomous_nav_guard.v bt_autonav_packet_rx.v
vlog -sv -work sim_sin12_unit tb_sin12_autonav.sv
vsim -c sim_sin12_unit.tb_sin12_autonav
run -all
quit -f
