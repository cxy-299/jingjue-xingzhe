# 手动新建 ModelSim 工程并观察波形

本说明只针对 ACG720 串口验收链路。**仿真顶层是 `tb_acg720_uart_bringup`，不是板卡顶层 `acg720_uart_bringup`，也不是教材例程 `mux2`。**测试平台实际例化 `vision_uart_bridge`，用串口电平发送真实格式的协议帧；板卡 LED 和尚未接入的电机不在此次行为仿真范围内。

## 1. 新建空工程

在 ModelSim 中选择 `File → New → Project`，名称可用 `acg720_uart_sim`，位置可用 `E:\gowin\ling_shu_vision\fpga\acg720_uart_bringup\modelsim_manual_project`。如果弹出是否创建 `work` 库，选择创建。旧的 `mux2` 工程不必修改。

## 2. 加入这 5 个现有文件

选择“Add Existing File / 添加已有文件”，尽量选择**引用原文件**而不是复制；按以下顺序加入并编译：

1. `E:\gowin\ling_shu_vision\fpga\uart_rx.v`：把 UART 电平解码成字节。
2. `E:\gowin\ling_shu_vision\fpga\vision_packet_parser.v`：验证帧头、长度、CRC，解码视觉字段。
3. `E:\gowin\ling_shu_vision\fpga\vision_uart_bridge.v`：把字节接收、帧解析和两个安全超时连接起来。
4. `E:\gowin\ling_shu_vision\fpga\acg720_uart_bringup\acg720_uart_bringup.v`：实体板卡 LED 顶层；此测试中只编译，不作为仿真顶层。
5. `E:\gowin\ling_shu_vision\fpga\acg720_uart_bringup\tb_acg720_uart_bringup.sv`：产生时钟、完整 UART 帧、CRC 错帧并自动判定结果。

**不要加入** `.gprj`、`.cst`、`.sdc`、`.fs`、`build.tcl` 或旧的 `run_modelsim.do`：它们不是手动 ModelSim 工程需要编译的 HDL。`.v` 文件按 Verilog 编译，`.sv` 测试平台按 SystemVerilog 编译。选择 `Compile → Compile All`，预期 `Errors: 0, Warnings: 0`。

## 3. 以保留信号的方式启动仿真

在 ModelSim 下方 Transcript 手动输入（新建工程默认库名为 `work`）：

```tcl
vsim -voptargs=+acc work.tb_acg720_uart_bringup
view wave
add wave -r sim:/tb_acg720_uart_bringup/*
run -all
```

顺序很重要：**先装载并添加波形，再运行**。`+acc` 让 ModelSim 保留测试平台和 DUT 信号；如果省略，优化后可能再次出现 `No objects found`。`add wave -r` 会加入测试平台及其 `dut` 子模块信号。如果 Wave 窗口被遮住，在 `View → Wave` 打开；运行结束后用 Wave 的 `Zoom Full` 看全程，再局部放大 UART 字节。

如果手工命令仍找不到信号，检查 Transcript 的 `vsim` 行是否真的写了 `work.tb_acg720_uart_bringup` 和 `-voptargs=+acc`，不要选 `acg720_uart_bringup` 或 `mux2`；然后在 ModelSim 的 Structure/Objects 窗口选中 `/tb_acg720_uart_bringup`，右键将信号加入 Wave。

## 4. 必看的信号及结果

测试平台顶层 `/tb_acg720_uart_bringup` 下有 `test_step`、`clk`、`rst_n`、`uart_rx`、`vision_pulses`、`link_alive`、`vision_fresh`、`target_valid`、`target_confirmed`、`crc_errors`、`class_id`、`center_error`、`frame_id`、`sequence_id`。`dut` 内部可继续看 `rx_byte`、`rx_byte_valid`、`vision_valid` 和 `heartbeat_valid`。

| test_step | 正在测试 | 关键期望 |
| --- | --- | --- |
| 0 | 复位 | `link_alive=0`、`vision_fresh=0`、`target_valid=0` |
| 1 | 正确心跳 | `link_alive=1`，但 `vision_fresh=0`、`target_valid=0` |
| 2 | 正确视觉帧 | `link_alive=1`、`vision_fresh=1`、`target_valid=1`、`target_confirmed=1`；类别 `42`、中心偏差 `-1234`、帧号 `0x12345678`、序号 `2` |
| 3 | 故意损坏 CRC | `crc_errors` 变为 `1`，`vision_pulses` 不增加 |
| 4 | 等待超时 | `link_alive=0`、`vision_fresh=0`、`target_valid=0` |
| 5 | 新视觉帧后发心跳 | 链路和视觉状态重新有效 |
| 6 | 只有心跳仍新鲜 | `link_alive=1`，但 `vision_fresh=0`、`target_valid=0` |
| 7 | 心跳也超时 | `link_alive=0` |
| 8 | 正确的“无目标”视觉帧 | `link_alive=1`、`vision_fresh=1`、`target_valid=0`；最终 `vision_pulses=3` |

测试平台将两个超时参数缩短为 5 ms 以加快仿真；真实 FPGA 顶层仍使用 1500 ms。全程约 25 ms **仿真时间**，不代表实际运行要等 25 ms。

最终 Transcript 必须出现：

```text
PASS tb_acg720_uart_bringup: UART, CRC, fields, heartbeat, timeouts, no-target
```

同时不能出现 `FAIL`、`Fatal` 或编译错误。仅看到波形、`Errors: 0`、或者自动结束，都**不能**代替这条 PASS。把完整 Transcript 末尾和 Wave 截图发给维护者确认后，再讨论 FPGA 下板；目前没有执行下载。
