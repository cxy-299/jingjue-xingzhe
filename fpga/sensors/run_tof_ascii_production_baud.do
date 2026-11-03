transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -sv ../uart_rx.v tof_ms53l2m_ascii_uart.v tb_tof_ascii_production_baud.sv
vsim -c work.tb_tof_ascii_production_baud
run -all
quit -f
