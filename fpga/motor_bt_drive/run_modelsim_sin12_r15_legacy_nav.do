onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r15_legacy_nav]} {vlib sim_sin12_r15_legacy_nav}
vlog -work sim_sin12_r15_legacy_nav heading_approach_control.v ../nav/nav_unsigned_divider.v ../nav/grid_bfs_dynamic.v ../nav/autonomous_nav_guard.v
vlog -sv -work sim_sin12_r15_legacy_nav tb_sin12_autonav.sv
vsim -c sim_sin12_r15_legacy_nav.tb_sin12_autonav
run -all
quit -f
