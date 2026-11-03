set PROJECT_ROOT [file normalize [file join [file dirname [info script]] ../..]]
cd [file dirname [info script]]
# ModelSim Transcript: do $PROJECT_ROOT/fpga/nav/run_modelsim.do
# Set cwd so readmemh finds the local map file.
cd $PROJECT_ROOT/fpga/nav
if {![file isdirectory sim_nav]} {vlib sim_nav}
vmap sim_nav sim_nav
vlog -work sim_nav ../uart_rx.v ../vision_packet_parser.v ../vision_uart_bridge.v fixed_grid_bfs.v acg720_nav_preview.v
vlog -sv -work sim_nav tb_fixed_grid_bfs.sv
vlog -sv -work sim_nav tb_acg720_nav_preview.sv
vsim -voptargs=+acc sim_nav.tb_fixed_grid_bfs
onfinish stop
view wave
add wave sim:/tb_fixed_grid_bfs/clk
add wave sim:/tb_fixed_grid_bfs/rst_n
add wave sim:/tb_fixed_grid_bfs/goal_valid
add wave sim:/tb_fixed_grid_bfs/goal_x
add wave sim:/tb_fixed_grid_bfs/goal_y
add wave sim:/tb_fixed_grid_bfs/busy
add wave sim:/tb_fixed_grid_bfs/ready
add wave sim:/tb_fixed_grid_bfs/no_path
add wave sim:/tb_fixed_grid_bfs/steps
add wave sim:/tb_fixed_grid_bfs/waypoint_valid
add wave sim:/tb_fixed_grid_bfs/wx
add wave sim:/tb_fixed_grid_bfs/wy
add wave sim:/tb_fixed_grid_bfs/dut/state
run -all
vsim -voptargs=+acc sim_nav.tb_acg720_nav_preview
view wave
add wave sim:/tb_acg720_nav_preview/clk
add wave sim:/tb_acg720_nav_preview/uart_rx
add wave sim:/tb_acg720_nav_preview/goal_pulses
add wave sim:/tb_acg720_nav_preview/dut/goal_x
add wave sim:/tb_acg720_nav_preview/dut/goal_y
add wave sim:/tb_acg720_nav_preview/dut/planner_busy
add wave sim:/tb_acg720_nav_preview/dut/route_ready
add wave sim:/tb_acg720_nav_preview/dut/no_path
add wave sim:/tb_acg720_nav_preview/dut/u_planner/path_steps_o
add wave sim:/tb_acg720_nav_preview/led
run -all
