onerror {quit -code 1 -f}
if {![file exists sim_sin9_tx]} {vlib sim_sin9_tx}
vlog -work sim_sin9_tx ../uart_rx.v ../bluetooth_bringup/uart_tx_echo.v bt_combined_diag_uart.v
vlog -sv -work sim_sin9_tx tb_sin9_telemetry.sv
vsim -c sim_sin9_tx.tb_sin9_telemetry
run -all
quit -f
