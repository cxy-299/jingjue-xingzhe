set PROJECT_ROOT [file normalize [file join [file dirname [info script]] ../..]]
cd [file dirname [info script]]
# 无 GUI 回归；与手动 Wave 脚本使用同一批 RTL 和测试平台。
cd $PROJECT_ROOT/fpga/nav
if {![file isdirectory sim_nav]} {vlib sim_nav}
vmap sim_nav sim_nav
vlog -work sim_nav ../uart_rx.v ../vision_packet_parser.v ../vision_uart_bridge.v fixed_grid_bfs.v acg720_nav_preview.v
vlog -sv -work sim_nav tb_fixed_grid_bfs.sv tb_acg720_nav_preview.sv
vsim -c sim_nav.tb_fixed_grid_bfs
onfinish stop
run -all
vsim -c sim_nav.tb_acg720_nav_preview
onfinish stop
run -all
quit -f
