onerror {quit -code 1 -f}
if {![file exists sim_video_startup]} {vlib sim_video_startup}
vlog -work sim_video_startup D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v sin12_video_startup.v sin12_dvi_encoder.v camera_vendor/src/vga/tmds_encode.v
vlog -sv -work sim_video_startup tb_video_startup.sv
vsim -c sim_video_startup.tb_video_startup
run -all
quit -f
