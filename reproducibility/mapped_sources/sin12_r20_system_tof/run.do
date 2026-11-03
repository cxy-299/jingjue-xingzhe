onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work]} {vlib work}
vlog -work work D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v mapped.v wrapper.v
vlog -sv +define+TOF_GATE -work work {E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/fpga/sensors/tb_tof_ascii_fault_recovery.sv}
vsim -wlf tof_r20_mapped.wlf work.tb_tof_ascii_fault_recovery
onfinish exit
run -all
quit -f
