onerror {quit -code 1 -f}
if {![file exists sim_camera_buffer]} {vlib sim_camera_buffer}
vlog -sv -work sim_camera_buffer sin12_video_startup.v sin12_camera_hdmi.v tb_camera_framebuffer.sv
vsim -c sim_camera_buffer.tb_camera_framebuffer
run -all
quit -f
