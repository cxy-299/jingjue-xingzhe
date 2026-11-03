onerror {quit -code 1 -f}
if {![file exists sim_pi_evidence]} {vlib sim_pi_evidence}
vlog -work sim_pi_evidence ../encoder_speed.v ../motor_pwm_dir.v ../bluetooth_bringup/uart_tx_echo.v ../motor_four_closed_loop/acg720_motor_four_closed_loop.v
vlog -sv -work sim_pi_evidence tb_pi_fault_evidence.sv
vsim -c sim_pi_evidence.tb_pi_fault_evidence
run -all
quit -f
