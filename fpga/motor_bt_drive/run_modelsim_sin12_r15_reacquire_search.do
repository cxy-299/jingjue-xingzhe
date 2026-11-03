onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r15_search]} {vlib sim_sin12_r15_search}
vlog -work sim_sin12_r15_search vision_mission_guard.v
vlog -sv -work sim_sin12_r15_search tb_sin12_r15_reacquire_search.sv
vsim -c sim_sin12_r15_search.tb_sin12_r15_reacquire_search
run -all
quit -f
