onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r17_wait_telemetry]} {vlib sim_sin12_r17_wait_telemetry}
vlog -work sim_sin12_r17_wait_telemetry ../uart_rx.v ../bluetooth_bringup/uart_tx_echo.v bt_combined_diag_uart.v
vlog -sv -work sim_sin12_r17_wait_telemetry tb_sin12_r17_wait_telemetry.sv
vsim -c sim_sin12_r17_wait_telemetry.tb_sin12_r17_wait_telemetry
run -all
quit -f
