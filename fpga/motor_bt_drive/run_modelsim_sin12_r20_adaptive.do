set PROJECT_ROOT [file normalize [file join [file dirname [info script]] ../..]]
cd [file dirname [info script]]
file mkdir $PROJECT_ROOT/tmp/adaptive
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists $PROJECT_ROOT/tmp/adaptive/work]} {vlib $PROJECT_ROOT/tmp/adaptive/work}
vlog -work $PROJECT_ROOT/tmp/adaptive/work $PROJECT_ROOT/fpga/motor_bt_drive/heading_approach_control.v $PROJECT_ROOT/fpga/nav/nav_unsigned_divider.v $PROJECT_ROOT/fpga/nav/grid_bfs_dynamic.v $PROJECT_ROOT/fpga/nav/autonomous_nav_guard.v
vlog -sv -work $PROJECT_ROOT/tmp/adaptive/work $PROJECT_ROOT/fpga/motor_bt_drive/tb_sin12_r20_adaptive.sv
vsim -c $PROJECT_ROOT/tmp/adaptive/work.tb_sin12_r20_adaptive
run -all
quit -f
