if {![file isdirectory motor_m1_sim]} {vlib motor_m1_sim}
vlog -work motor_m1_sim ../motor_pwm_dir.v acg720_motor_m1_bringup.v
vlog -sv -work motor_m1_sim tb_acg720_motor_m1_bringup.sv
vsim -c -voptargs=+acc motor_m1_sim.tb_acg720_motor_m1_bringup
run -all
quit -f
