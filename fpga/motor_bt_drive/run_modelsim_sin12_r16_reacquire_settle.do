onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r16_settle]} {vlib sim_sin12_r16_settle}
vlog -work sim_sin12_r16_settle vision_mission_guard.v
vlog -sv -work sim_sin12_r16_settle tb_sin12_r16_reacquire_settle.sv
vsim -c sim_sin12_r16_settle.tb_sin12_r16_reacquire_settle
run -all
quit -f
