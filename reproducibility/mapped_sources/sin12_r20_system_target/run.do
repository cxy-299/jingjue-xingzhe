onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists tmp/sin12_r20_system_target/sim]} {vlib tmp/sin12_r20_system_target/sim}
vlog -work tmp/sin12_r20_system_target/sim D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_system_target/mapped.v E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_system_target/wrapper.v
vlog -sv +define+GOWIN_GATE -work tmp/sin12_r20_system_target/sim fpga/motor_bt_drive/tb_sin12_r7_target.sv
vsim -c tmp/sin12_r20_system_target/sim.tb_sin12_r7_target
run -all
quit -f
