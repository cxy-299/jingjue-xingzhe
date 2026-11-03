onerror {quit -code 1 -f}
if {![file exists sim_sin12_r13_map_nav]} {vlib sim_sin12_r13_map_nav}
vlog -work sim_sin12_r13_map_nav heading_approach_control.v ../nav/nav_unsigned_divider.v ../nav/grid_bfs_dynamic.v ../nav/autonomous_nav_guard.v
vlog -sv -work sim_sin12_r13_map_nav tb_sin12_r9_map_nav.sv
vsim -c sim_sin12_r13_map_nav.tb_sin12_r9_map_nav
run -all
quit -f
