# BTD6：蓝牙终点帧 -> FPGA CRC/地图校验 -> 固定地图 BFS -> 编码器路点闭环。
# 仅生成位流，不调用 Programmer；上板前必须先完成 ModelSim 回归和离地测试。
open_project E:/gowin/ling_shu_vision/fpga/motor_bt_drive/acg720_motor_bt_nav.gprj
set_option -top_module acg720_motor_bt_nav
set_option -user_code 42544436
run all
