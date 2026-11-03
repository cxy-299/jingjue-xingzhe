if {![file isdirectory sim_four]} {vlib sim_four}
vlog -work sim_four ../motor_pwm_dir.v ../motor_m1_bringup/acg720_motor_m1_toggle_50.v acg720_motor_four_kick_80.v
vlog -sv -work sim_four tb_acg720_motor_four_kick_80.sv
vsim -c -voptargs=+acc sim_four.tb_acg720_motor_four_kick_80
run -all
quit -f
