# ACG720 导航 LED 预览工程：综合、布局布线并生成 SRAM 下载位流。
# 不调用 Programmer，不会操作已连接的板卡；在 Gowin gw_sh.exe 中执行。
open_project E:/gowin/ling_shu_vision/fpga/nav/acg720_nav_preview.gprj
set_option -top_module acg720_nav_preview
# 板载联调版本标记：可用 Programmer 的 Read User Code 只读确认位流已切换。
set_option -user_code 4E415633
run all
