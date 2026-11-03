set PROJECT_ROOT [file normalize [file join [file dirname [info script]] ../..]]
cd [file dirname [info script]]
file mkdir $PROJECT_ROOT/tmp
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists $PROJECT_ROOT/tmp/sin12_r18_left_detour]} {vlib $PROJECT_ROOT/tmp/sin12_r18_left_detour}
vlog -work $PROJECT_ROOT/tmp/sin12_r18_left_detour $PROJECT_ROOT/fpga/motor_bt_drive/heading_approach_control.v $PROJECT_ROOT/fpga/nav/nav_unsigned_divider.v $PROJECT_ROOT/fpga/nav/grid_bfs_dynamic.v $PROJECT_ROOT/fpga/nav/autonomous_nav_guard.v
vlog -sv -work $PROJECT_ROOT/tmp/sin12_r18_left_detour $PROJECT_ROOT/fpga/motor_bt_drive/tb_sin12_r18_left_detour.sv
vsim -c $PROJECT_ROOT/tmp/sin12_r18_left_detour.tb_sin12_r18_left_detour
run -all
quit -f
