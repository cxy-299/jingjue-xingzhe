# SIN5：M3 起转隔离试验，四轮起步间隔由 40 ms 调至 125 ms。
# ToF 无有效帧时禁止运动；250 mm 内硬停，251--799 mm 按比例减速。
open_project E:/gowin/ling_shu_vision/fpga/motor_bt_drive/acg720_motor_bt_nav.gprj
set_option -top_module acg720_motor_bt_nav
set_option -user_code 53494E35
run all
