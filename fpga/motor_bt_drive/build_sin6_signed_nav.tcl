# SIN6: preserve SIN5 motor/sensor controls; correct signed encoder distance
# accumulation in the FPGA route executor. Build only; never programs board.
open_project E:/gowin/ling_shu_vision/fpga/motor_bt_drive/acg720_motor_bt_nav.gprj
set_option -top_module acg720_motor_bt_nav
set_option -user_code 53494E36
run all
