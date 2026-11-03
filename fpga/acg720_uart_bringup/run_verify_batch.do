# 无界面复现 UART 验收：编译、运行自检、导出关键波形供报告使用。
transcript file uart_verify.log
if {![file exists verify_work/_info]} {vlib verify_work}
vmap verify_work verify_work
vlog -work verify_work ../uart_rx.v ../vision_packet_parser.v ../vision_uart_bridge.v
vlog -sv -work verify_work tb_acg720_uart_bringup.sv
vsim -voptargs=+acc -t 1ps verify_work.tb_acg720_uart_bringup
vcd file uart_verify.vcd
vcd add /tb_acg720_uart_bringup/test_step
vcd add /tb_acg720_uart_bringup/uart_rx
vcd add /tb_acg720_uart_bringup/link_alive
vcd add /tb_acg720_uart_bringup/vision_fresh
vcd add /tb_acg720_uart_bringup/target_valid
vcd add /tb_acg720_uart_bringup/target_confirmed
vcd add /tb_acg720_uart_bringup/vision_pulse
vcd add /tb_acg720_uart_bringup/vision_pulses
vcd add /tb_acg720_uart_bringup/crc_errors
vcd add /tb_acg720_uart_bringup/center_error
vcd add /tb_acg720_uart_bringup/frame_id
run -all
quit -f
