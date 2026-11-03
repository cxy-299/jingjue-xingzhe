onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_sin12_r14_recovery]} {vlib sim_sin12_r14_recovery}
vlog -work sim_sin12_r14_recovery vision_mission_guard.v
vlog -sv -work sim_sin12_r14_recovery tb_sin12_r14_target_recovery.sv
vsim -c sim_sin12_r14_recovery.tb_sin12_r14_target_recovery
run -all
quit -f
