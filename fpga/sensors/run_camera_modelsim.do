transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -sv ov5640_dvp_capture.v tb_ov5640_dvp_capture.sv
vsim -c work.tb_ov5640_dvp_capture
run -all
quit -f
