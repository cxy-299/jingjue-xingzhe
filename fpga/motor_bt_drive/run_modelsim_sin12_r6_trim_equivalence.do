onerror {quit -code 1 -f}
if {![file exists sim_sin12_r6_trim_equivalence]} {vlib sim_sin12_r6_trim_equivalence}
vlog -work sim_sin12_r6_trim_equivalence chassis_trim.v
vlog -sv -work sim_sin12_r6_trim_equivalence tb_sin12_r6_trim_equivalence.sv
vsim -c sim_sin12_r6_trim_equivalence.tb_sin12_r6_trim_equivalence
run -all
quit -f
