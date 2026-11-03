onerror {quit -code 1 -f}
if {![file exists sim_native_tmds]} {vlib sim_native_tmds}
vlog -work sim_native_tmds D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v sin12_dvi_encoder.v camera_vendor/src/vga/tmds_encode.v
vlog -sv -work sim_native_tmds tb_native_tmds.sv
vsim -c sim_native_tmds.tb_native_tmds
run -all
quit -f
