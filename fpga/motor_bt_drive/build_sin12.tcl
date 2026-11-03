cd E:/gowin/ling_shu_vision/fpga/motor_bt_drive
open_project E:/gowin/ling_shu_vision/fpga/motor_bt_drive/acg720_motor_bt_autonav.gprj
set_option -top_module acg720_motor_bt_autonav
set_option -user_code 534E3241
# Fast development route; retain timing-driven optimization and the real SDC.
# 0 = congestion/default, 1 = timing-oriented, 2 = faster route algorithm.
set_option -route_option 2
set_option -timing_driven 1
run all
