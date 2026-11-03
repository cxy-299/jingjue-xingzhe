set project_dir [file normalize [file dirname [info script]]]
cd $project_dir
open_project [file join $project_dir sin12_hdmi_system.gprj]
set_option -top_module sin12_hdmi_system
set_option -user_code 534E3254
set_option -opt_goal timing
set_option -place_option 0
set_option -route_option 2
set_option -timing_driven 1
set_option -replicate_resources 1
set_option -use_sspi_as_gpio 1
run all
