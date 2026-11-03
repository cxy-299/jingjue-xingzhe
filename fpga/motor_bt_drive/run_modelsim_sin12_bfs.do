onerror {quit -code 1 -f}
if {![file exists sim_sin12_bfs]} {vlib sim_sin12_bfs}
vlog -work sim_sin12_bfs ../nav/grid_bfs_dynamic.v
vlog -sv -work sim_sin12_bfs tb_sin12_bfs.sv
vsim -c sim_sin12_bfs.tb_sin12_bfs
run -all
quit -f
