# ModelSim 无许可证时，用 Vivado XSIM 对同一份 testbench 做独立仿真。
# 只导出验收要看的信号，避免将 50 MHz 时钟写进巨大的 VCD。
open_vcd uart_verify_xsim.vcd
log_vcd /tb_acg720_uart_bringup/test_step
log_vcd /tb_acg720_uart_bringup/uart_rx
log_vcd /tb_acg720_uart_bringup/link_alive
log_vcd /tb_acg720_uart_bringup/vision_fresh
log_vcd /tb_acg720_uart_bringup/target_valid
log_vcd /tb_acg720_uart_bringup/target_confirmed
log_vcd /tb_acg720_uart_bringup/vision_pulse
log_vcd /tb_acg720_uart_bringup/vision_pulses
log_vcd /tb_acg720_uart_bringup/crc_errors
log_vcd /tb_acg720_uart_bringup/center_error
log_vcd /tb_acg720_uart_bringup/frame_id
run all
close_vcd
quit
