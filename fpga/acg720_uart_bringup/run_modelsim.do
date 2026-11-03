# 可选的一键仿真；手动建工程请看 MODELSIM_MANUAL_CN.md。
transcript file modelsim_uart_test.log
if {![file exists sim_work/_info]} {vlib sim_work}
vmap sim_work sim_work
vlog -work sim_work ../uart_rx.v ../vision_packet_parser.v ../vision_uart_bridge.v acg720_uart_bringup.v
vlog -sv -work sim_work tb_acg720_uart_bringup.sv
# +acc 保留信号供 Wave 窗口观察，避免 vopt 优化后找不到对象。
vsim -voptargs=+acc -t 1ps sim_work.tb_acg720_uart_bringup
view wave
add wave -r sim:/tb_acg720_uart_bringup/*
run -all
