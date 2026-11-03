onerror {quit -code 1 -f}
if {![file exists sim_sin11_telemetry]} {vlib sim_sin11_telemetry}
vlog -work sim_sin11_telemetry ../bluetooth_bringup/uart_tx_echo.v ../uart_rx.v bt_combined_diag_uart.v
vlog -sv -work sim_sin11_telemetry tb_sin11_telemetry.sv
vsim -c sim_sin11_telemetry.tb_sin11_telemetry
run -all
quit -f
