# Build the isolated 100 mm hard-stop experimental variant; never program board.
open_project E:/gowin/ling_shu_vision/fpga/motor_bt_drive/acg720_motor_bt_nav.gprj
set_option -top_module acg720_motor_bt_nav_10cm
set_option -user_code 53494E38
run all
