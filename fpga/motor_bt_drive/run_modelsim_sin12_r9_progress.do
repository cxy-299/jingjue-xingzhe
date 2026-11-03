onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r9_progress]} {vlib sim_sin12_r9_progress}
vlog -work sim_sin12_r9_progress heading_approach_control.v ../nav/nav_unsigned_divider.v ../nav/grid_bfs_dynamic.v ../nav/autonomous_nav_guard.v
vlog -sv -work sim_sin12_r9_progress tb_sin12_r9_progress.sv
vsim -c sim_sin12_r9_progress.tb_sin12_r9_progress
run -all
quit -f
