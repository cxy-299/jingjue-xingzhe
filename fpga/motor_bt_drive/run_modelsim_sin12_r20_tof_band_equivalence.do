set PROJECT_ROOT [file normalize [file join [file dirname [info script]] ../..]]
cd [file dirname [info script]]
file mkdir $PROJECT_ROOT/tmp/tof_band
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists $PROJECT_ROOT/tmp/tof_band/work]} {vlib $PROJECT_ROOT/tmp/tof_band/work}
vlog -work $PROJECT_ROOT/tmp/tof_band/work $PROJECT_ROOT/fpga/sensors/tof_obstacle_guard.v
vlog -sv -work $PROJECT_ROOT/tmp/tof_band/work $PROJECT_ROOT/fpga/motor_bt_drive/tb_sin12_r20_tof_band_equivalence.sv
vsim -c $PROJECT_ROOT/tmp/tof_band/work.tb_sin12_r20_tof_band_equivalence
run -all
quit -f
