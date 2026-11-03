onerror {quit -code 1 -f}
if {![file exists sim_sin10_telemetry]} {vlib sim_sin10_telemetry}
vlog -work sim_sin10_telemetry ../bluetooth_bringup/uart_tx_echo.v ../uart_rx.v bt_combined_diag_uart.v
vlog -sv -work sim_sin10_telemetry tb_sin10_telemetry.sv
vsim -c sim_sin10_telemetry.tb_sin10_telemetry
run -all
quit -f
