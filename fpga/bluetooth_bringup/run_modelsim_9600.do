if {![file isdirectory sim_bt_echo]} {vlib sim_bt_echo}
vlog -work sim_bt_echo ../uart_rx.v uart_tx_echo.v acg720_bt_echo.v
vlog -sv -work sim_bt_echo tb_acg720_bt_echo.sv
vsim -c -voptargs=+acc -gTB_CLK_HZ=50000000 -gTB_BAUD=9600 sim_bt_echo.tb_acg720_bt_echo
run -all
quit -f
