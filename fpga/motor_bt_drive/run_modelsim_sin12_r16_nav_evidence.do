onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r16_nav]} {vlib sim_sin12_r16_nav}
vlog -work sim_sin12_r16_nav heading_approach_control.v ../nav/nav_unsigned_divider.v ../nav/grid_bfs_dynamic.v ../nav/autonomous_nav_guard.v
vlog -sv -work sim_sin12_r16_nav tb_sin12_r16_nav_evidence.sv
vsim -c sim_sin12_r16_nav.tb_sin12_r16_nav_evidence
run -all
quit -f
