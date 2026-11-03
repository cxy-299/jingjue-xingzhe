onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_mapped_nav/sim]} {vlib E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_mapped_nav/sim}
vlog -work E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_mapped_nav/sim D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_mapped_nav/mapped.v
vlog -sv -work E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_mapped_nav/sim E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/fpga/motor_bt_drive/tb_sin12_r20_mapped_nav.sv
vsim -c E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/tmp/sin12_r20_mapped_nav/sim.tb_sin12_r20_mapped_nav
run -all
quit -f
