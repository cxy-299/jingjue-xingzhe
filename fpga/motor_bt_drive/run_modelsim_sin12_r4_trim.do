onerror {quit -code 1 -f}
if {![file exists sim_sin12_r4_trim]} {vlib sim_sin12_r4_trim}
vlog -work sim_sin12_r4_trim chassis_trim.v
vlog -sv -work sim_sin12_r4_trim tb_sin12_r4_trim.sv
vsim -c sim_sin12_r4_trim.tb_sin12_r4_trim
run -all
quit -f
