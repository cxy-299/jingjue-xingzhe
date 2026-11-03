onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r12_lateral_trim]} {vlib sim_sin12_r12_lateral_trim}
vlog -work sim_sin12_r12_lateral_trim chassis_trim.v
vlog -sv -work sim_sin12_r12_lateral_trim tb_sin12_r10_lateral_trim.sv
vsim -c sim_sin12_r12_lateral_trim.tb_sin12_r10_lateral_trim
run -all
quit -f
