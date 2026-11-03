if {[file exists sim_motor_encoder_uart]} {vdel -lib sim_motor_encoder_uart -all}
vlib sim_motor_encoder_uart
vmap sim_motor_encoder_uart sim_motor_encoder_uart
vlog -work sim_motor_encoder_uart ../encoder_speed.v ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v ../motor_m1_bringup/acg720_motor_m1_kick_80.v ../motor_encoder_decimal/seg7_hc595_scan.v ../motor_encoder_decimal/acg720_motor_encoder_decimal.v ../bluetooth_bringup/uart_tx_echo.v acg720_motor_encoder_uart.v
vlog -sv -work sim_motor_encoder_uart tb_acg720_motor_encoder_uart.sv
vsim -c -voptargs=+acc sim_motor_encoder_uart.tb_acg720_motor_encoder_uart
run -all
quit -sim
