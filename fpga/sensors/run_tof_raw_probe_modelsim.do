transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -sv ../uart_rx.v ../bluetooth_bringup/uart_tx_echo.v tof_ms53l2m_ascii_uart.v tof_single_bringup.v tof_single_raw_probe.v tb_tof_single_raw_probe.sv
vsim -c work.tb_tof_single_raw_probe
run -all
quit -f
