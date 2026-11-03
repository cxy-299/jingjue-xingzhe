cd E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/fpga/sin12_hdmi
open_project E:/gowin/ling_shu_vision/candidates/sin12_r20_20261102/fpga/sin12_hdmi/sin12_hdmi_system.gprj
set_option -top_module sin12_hdmi_system
set_option -user_code 534E3254
set_option -opt_goal timing
set_option -place_option 0
set_option -route_option 2
set_option -timing_driven 1
set_option -replicate_resources 1
set_option -use_sspi_as_gpio 1
run pnr
