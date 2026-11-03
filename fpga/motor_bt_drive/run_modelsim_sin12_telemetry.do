onerror {quit -code 1 -f}
if {![file exists sim_sin12_telemetry]} {vlib sim_sin12_telemetry}
vlog -work sim_sin12_telemetry ../bluetooth_bringup/uart_tx_echo.v ../uart_rx.v bt_combined_diag_uart.v
vlog -sv -work sim_sin12_telemetry tb_sin12_telemetry.sv
vsim -c sim_sin12_telemetry.tb_sin12_telemetry
run -all
quit -f
