# ACG720-GW5AT60 串口接收验收工程

## 当前状态（2026-10-14）

2026-10-14 已用当前源码重新生成 `impl/pnr/acg720_uart_bringup.fs`，ModelSim 自检 PASS，50 MHz 时序无 setup/hold 违例。高云下载器及 `GW5AT-60B` 已识别；**仅写入过易失性 SRAM，未擦写 Flash**，用户目视确认 LED2 闪烁。树莓派到 FPGA 的串口链路仍未验证通过，详见 [板载验收记录](../../BOARD_UART_GUI_ACCEPTANCE_CN.md)。

本工程只接收视觉串口并显示板载 LED，**不包含电机输出**，适合先验收串口。电机驱动接入之前不要用它代替完整机器人顶层。

代码按四个职责划分，维护时从上到下排查即可：`uart_rx.v` 把串口电平变成字节；`vision_packet_parser.v` 检查帧头、长度、版本和 CRC，完整有效后才更新识别字段；`vision_uart_bridge.v` 分别计算通信存活和视觉结果新鲜度；`acg720_uart_bringup.v` 把状态映射到板载 LED。这次只简化仿真脚本并补关键注释，没有改动 RTL 的综合行为。

## 两条不同的线

1. **下载线**：电脑 USB → 高云兼容 USB-JTAG 下载器 → 开发板 JTAG 下载接口。它负责把 `.fs` 写入 FPGA。单独的 USB-A 转 USB-C 串口线不能完成这一步。
2. **运行串口线**：树莓派 USB-A → 开发板板载 CH340E 串口的 Type-C 口。它只传送 YOLO 结果，不负责下载 FPGA 程序。不要误插 12V 电源接口，也不要把树莓派 5V 接到 FPGA IO。

板卡已经单独供电时，接线前仍应核对接口丝印和下载器方向；不确定 JTAG 排针位置时先拍接口近照，不要把下载器插到黄色 GPIO 排针上。

## 下载和验收

### 先做 ModelSim 仿真

如果希望自己新建工程、手动选顶层并观察每个信号，请按 [ModelSim 手动仿真说明](MODELSIM_MANUAL_CN.md) 操作；下述 `.do` 脚本仅为快捷方式。

本工程的 ModelSim 脚本是 `run_modelsim.do`，自检测试平台是 `tb_acg720_uart_bringup.sv`。打开 ModelSim，在下方 Transcript 输入：

```tcl
cd {E:/gowin/ling_shu_vision/fpga/acg720_uart_bringup}
do run_modelsim.do
```

脚本会依次建立仿真库、按 Verilog 模式编译生产 RTL、按 SystemVerilog 模式编译测试平台、以 `+acc` 保留信号、加入 Wave 并执行 `run -all`。以 Transcript 最后出现 `PASS tb_acg720_uart_bringup: UART, CRC, fields, heartbeat, timeouts, no-target`，且此前没有 `FAIL`、`Fatal` 或编译错误，作为串口验收仿真通过的条件。测试中故意损坏一帧，CRC 错误计数应增加一次；仅心跳不能保持视觉目标有效，超时后目标必须失效。

测试平台为加速仿真，把两个安全超时参数缩短到 5 ms；下板顶层使用 1500 ms。测试范围是 UART 接收、协议解析及失联/视觉超时门控，不覆盖尚未接入的电机和传感器。2026-10-10 用户提供的 ModelSim 日志显示编译 0 错误、0 警告，且仿真已装载；但旧脚本添加波形失败，尚无 PASS。必须用新版脚本跑出上述 PASS，再进行下载。

1. 将 USB-JTAG 下载器连接电脑和开发板，保持开发板独立供电。确认电脑设备管理器出现下载器。
2. 在电脑上只读扫描：

   ```powershell
   & 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe' --scan-cables
   & 'D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe' --scan
   ```

   第二条必须识别出 `GW5AT-60B` 或对应的 GW5AT60 器件后才可继续；不匹配时停止。
3. 当前位流的 `security_bit_enable = true`。高云官方文档说明带安全位的 SRAM 配置不能读回验证；实测 `SRAM Program and Verify` 在写入后报 `Verify failed at 0`，而板上 LED2 已闪烁。因此应只选易失性 **SRAM Program**（CLI `--operation_index 2`）并载入 `impl/pnr/acg720_uart_bringup.fs`，不擦写板上 Flash。断电后本次 SRAM 配置会丢失，重新上电时按板卡已有的非易失配置启动（如果存在）。不要选择带 `Erase`、`Flash` 的操作。
4. 下载成功后，观察实体 `LED2` 以约 1.34 秒为周期闪烁，证明新代码正在运行。按 `S0` 可重置接收状态。
5. 将树莓派 USB-A 接到开发板 **CH340E UART Type-C**。树莓派上检查 `/dev/ttyUSB*` 或 `/dev/serial/by-id/`。当前 `config/config-pi.yaml` 使用 `auto_usb_ch340`：仅发现一块 CH340 时自动连接；有多块时需手动填准确端口。参数 `115200 8-N-1`。
6. 收到有效心跳后 `LED3` 亮；收到新鲜视觉帧后 `LED4` 亮；目标有效 `LED5` 亮；目标连续确认 `LED6` 亮；CRC 或 UART 帧错误出现后 `LED7` 锁存亮起。后四项需要真实有效的协议帧，插上线本身不会点亮。

## LED 与安全含义

| 板载 LED | 说明 |
| --- | --- |
| LED2 | 50 MHz 时钟运行指示，闪烁周期约 1.34 秒 |
| LED3 | 最近 1.5 秒收到 CRC 正确的视觉帧或心跳 |
| LED4 | 最近 1.5 秒收到 CRC 正确的视觉帧；仅心跳不能保持此灯 |
| LED5 | 视觉帧新鲜且目标有效 |
| LED6 | 视觉帧新鲜且目标已确认 |
| LED7 | 发生过 CRC 或 UART 帧错误；按 S0 清除 |

物理 LED0/LED1 在该 FPGA 封装中对应专用配置引脚，因此本工程只使用 LED2–LED7。

## 重新构建

双击 `acg720_uart_bringup.gprj` 可在 Gowin IDE 中打开。命令行构建：

```powershell
& 'D:\software\gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' 'E:\gowin\ling_shu_vision\fpga\acg720_uart_bringup\build.tcl'
```

本次构建在 50 MHz 约束下没有 setup/hold 违例。该结果是静态时序检查，不能替代下载后实机串口测试。
