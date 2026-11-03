onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists sim_r15_route_pipe]} {vlib sim_r15_route_pipe}
vlog -work sim_r15_route_pipe nav_route_executor.v
vlog -sv -work sim_r15_route_pipe tb_nav_route_executor_pipeline.sv tb_nav_route_executor_signed.sv
vsim -c sim_r15_route_pipe.tb_nav_route_executor_pipeline
run -all
quit -f
