set PROJECT_ROOT [file normalize [file join [file dirname [info script]] ../..]]
cd [file dirname [info script]]
file mkdir $PROJECT_ROOT/tmp
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists $PROJECT_ROOT/tmp/sin12_r17_two_stage]} {vlib $PROJECT_ROOT/tmp/sin12_r17_two_stage}
vlog -work $PROJECT_ROOT/tmp/sin12_r17_two_stage $PROJECT_ROOT/fpga/motor_bt_drive/mission_two_stage_approach.v $PROJECT_ROOT/fpga/motor_bt_drive/vision_mission_guard.v
vlog -sv -work $PROJECT_ROOT/tmp/sin12_r17_two_stage $PROJECT_ROOT/fpga/motor_bt_drive/tb_sin12_r17_two_stage.sv
vsim -c $PROJECT_ROOT/tmp/sin12_r17_two_stage.tb_sin12_r17_two_stage
run -all
quit -f
