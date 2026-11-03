# 赛题三优化与 YOLO 串口接入 FPGA 手册

状态更新（2026-10-16）：本文保留早期接入说明，其中“尚未下载”等历史状态不作为当前验收结论。官方六项任务对照、NAV3 历史板测和本轮未部署优化，统一见 [逻辑审查报告](output/review/TOPIC3_LOGIC_AUDIT_2026-10-16_CN.md)；当前机器人完整自主导航仍未完成。

## 1. 赛题对应关系

《高云.pdf》的选题三要求系统以 FPGA 构建机器人实时控制系统，边缘 AI 平台
负责视觉识别和场景理解。评分中 FPGA 实时感知与控制占 40%，系统稳定性占
25%，自主导航占 20%，AI 扩展功能占 5%。

本工程按以下职责拆分：

```text
Camera Module 3 -> Raspberry Pi 4B -> YOLO11n
                                      |
                                      | UART：纯视觉结果
                                      v
                                   Gowin FPGA
              +-----------------------+-----------------------+
              | ToF/超声波避障 | 搜索/跟随决策 | 编码器 PID |
              | 麦轮运动学      | PWM/方向输出  | 失联停车   |
              +-----------------------------------------------+
```

树莓派不发送电机 PWM，也不直接决定前进速度。它只发送 YOLO 识别结果；FPGA
结合 ToF、IMU 和编码器完成实时决策与运动控制。

## 2. 硬件连接

ACG720 首次联调建议先使用[无电机输出的串口验收工程](fpga/acg720_uart_bringup/README_CN.md)，完成下载和 LED 接收验证后再接入电机。该工程目前已生成位流，但尚未下载到 FPGA。

当前采用板载 USB 串口：树莓派 USB-A → ACG720 的 CH340E UART Type-C。`config/config-pi.yaml` 使用 `auto_usb_ch340`，仅在找到唯一 CH340 时自动连接；若插有多块 CH340，请改成确切的 `/dev/serial/by-id/...`。这条线不承担 FPGA JTAG 下载。

下述 GPIO14/GND 接法是另一种直连方案，与板载 USB 串口接法二选一，不要把两种发送端同时接到 FPGA 的 UART_RX。

树莓派使用 3.3V TTL UART：

| 树莓派 40Pin | 连接对象 |
| --- | --- |
| 物理引脚 8，GPIO14/TXD | FPGA 的 3.3V UART_RX |
| 物理引脚 6，GND | FPGA GND |

当前协议为树莓派单向发送，因此只连接 TX 和公共地即可。不要连接树莓派 5V
引脚，也不要把 5V UART 信号直接接入树莓派或 FPGA。FPGA 的具体管脚编号应
按照实际 ACG720/ACG750/BX72 板卡原理图写入高云约束文件。

串口参数固定为：

```text
115200 baud, 8 data bits, no parity, 1 stop bit (8-N-1)
```

## 3. 树莓派配置

此前已配置过 GPIO UART `/dev/serial0`，但当前 USB-A→板载 Type-C 接线
**不经过 GPIO UART**；本次不需要动这些系统设置。项目配置位于：

```text
/home/pi/ling_shu_vision/config/config-pi.yaml
```

比赛实机配置：

```yaml
serial:
  enabled: true
  port: auto_usb_ch340
  baudrate: 115200
  timeout: 0.0
  write_timeout: 0.1
  reconnect_interval_s: 2.0
  heartbeat_interval_ms: 500

mock_fpga:
  enabled: false
```

串口断开或设备暂时不存在时，YOLO 和网页不会退出；程序每 2 秒自动尝试重新
连接。网页“UART 发送诊断”区域显示实际 USB 端口、已发送帧/字节数、最近帧序号和错误。由于当前为单向
UART，“端口已打开”只表示树莓派能够写入本地 UART，并不能证明 FPGA 或电脑
已经收到数据；必须通过接收端串口助手或 FPGA 状态信号完成端到端确认。

## 4. 串口帧格式

所有多字节整数均为小端序。

| 字节 | 字段 | 说明 |
| --- | --- | --- |
| 0..1 | 帧头 | 固定 `AA 55` |
| 2 | 协议版本 | 当前为 `03` |
| 3 | 消息类型 | 心跳 `01`，视觉结果 `13` |
| 4..5 | 序号 | uint16，逐包递增 |
| 6..7 | 载荷长度 | uint16 |
| 8..N | 载荷 | 见下一节 |
| N+1..N+2 | CRC16 | CRC16-CCITT，初值 `FFFF`，小端序 |

CRC 范围从“协议版本”开始，到载荷最后一个字节结束，不包含 `AA 55` 和 CRC
本身。

### 4.1 视觉结果 `0x13`

载荷固定 26 字节，整帧共 36 字节：

| 载荷偏移 | 类型 | 字段 | 含义 |
| --- | --- | --- | --- |
| 0..3 | uint32 | timestamp_ms | 树莓派单调时钟毫秒 |
| 4..7 | uint32 | frame_id | 推理帧编号 |
| 8 | uint8 | flags | bit0 有目标，bit1 已确认，bit2 已居中 |
| 9 | uint8 | alignment | 0保持、1搜索、2左、3右、4居中、255错误 |
| 10..11 | uint16 | class_id | COCO/自训练模型类别编号；无目标为 `FFFF` |
| 12..13 | uint16 | confidence | 置信度乘以 10000 |
| 14..15 | uint16 | cx | 目标中心 X，归一化到 0..10000 |
| 16..17 | uint16 | cy | 目标中心 Y，归一化到 0..10000 |
| 18..19 | uint16 | width | 目标宽度，归一化到 0..10000 |
| 20..21 | uint16 | height | 目标高度，归一化到 0..10000 |
| 22..23 | int16 | center_error | 水平偏差，-10000..10000 |
| 24..25 | uint16 | area_ratio | 目标框面积比例乘以 10000 |

目标暂时丢失时仍发送视觉结果包，但 flags 的 bit0/bit1 清零；FPGA 不应沿用
上一帧的前进命令。

当前 Pi 配置选择 COCO `bottle` 类。代码已有可选 HSV 红色二次筛选和合成图测试，
但 `config/config-pi.yaml` 默认关闭，必须先用实拍红瓶/蓝瓶/红背景标定后再启用；
不能把普通瓶子检测或离线测试当作赛题红色水瓶目标已完成。

### 4.2 心跳 `0x01`

载荷为 4 字节运行时间 `uptime_ms`。FPGA 连续 1500 ms 没有收到 CRC 正确的
视觉包或心跳时，必须清零所有速度/PWM 输出。

## 5. FPGA RTL 接入

可综合模块位于 `fpga/`：

```text
uart_rx.v
vision_packet_parser.v
vision_uart_bridge.v
vision_motion_controller.v
mecanum_kinematics.v
encoder_speed.v
wheel_pi.v
motor_pwm_dir.v
fpga_robot_core.v
```

`fpga_robot_core.v` 是板卡无关的完整控制入口：它把视觉 UART、ToF 有效距离、
四路编码器和急停信号接入安全决策、麦轮运动学、四路 PI 速度环以及 PWM/方向
输出。运动命令采用 milli-unit，`1000` 表示归一化速度 `1.000`；默认控制周期
为 100 Hz，PWM 为 20 kHz。`tb_motion_controller.v` 提供策略层的 Verilog-2001
冒烟仿真用例。

顶层例化示例：

```verilog
vision_uart_bridge #(
    .CLK_HZ(50_000_000),
    .BAUD(115200),
    .WATCHDOG_MS(1500)
) u_vision_uart (
    .clk(clk_50m),
    .rst_n(rst_n),
    .pi_uart_rx_i(pi_uart_rx),
    .link_alive_o(vision_link_alive),
    .target_valid_o(vision_target_valid),
    .target_confirmed_o(vision_target_confirmed),
    .center_error_o(vision_center_error),
    .area_ratio_o(vision_area_ratio)
    // 其余端口按需连接
);
```

安全优先级建议：

```text
急停 > ToF硬停车 > UART失联 > 目标无效 > 正常导航/跟随
```

只有下面条件同时满足时才允许目标跟随：

```text
vision_link_alive && vision_target_valid && vision_target_confirmed
```

## 6. 联调步骤

本阶段优先执行 [无电机板载验收清单](BOARD_UART_GUI_ACCEPTANCE_CN.md)。
2×2 米地图与右下角起点暂记录在 `config/map-2m-stage1.yaml`，当前视觉/UART 程序
不会读取地图，也不会产生导航运动命令。

### 6.1 不接摄像头的确定性串口测试

先停止 GUI，避免两个程序同时打开串口：

```bash
sudo systemctl stop ling-shu-vision-gui.service
cd /home/pi/ling_shu_vision
./.venv/bin/python -m scripts.serial_fpga_test --count 10
sudo systemctl start ling-shu-vision-gui.service
```

测试程序交替发送“目标偏左”和“目标偏右”的水瓶结果。FPGA 应交替得到
`alignment=2/3` 和 `center_error=-4000/+4000`，CRC 错误计数应保持 0。

### 6.2 实时 YOLO 联调

1. 打开 `http://192.168.137.129:8080`；
2. 确认“FPGA 串口”显示“已连接”；
3. 将目标从画面左侧移动到右侧；
4. FPGA 观察 `center_error` 从负数过零后变为正数；
5. 遮挡目标，确认 `target_valid_o` 清零；
6. 断开 UART 或停止视觉服务，确认 1500 ms 后 `link_alive_o` 清零并停车。

### 6.3 使用 Windows 电脑代替 FPGA 接收

准备 USB 转 TTL 模块，只连接以下两根线：

```text
树莓派物理引脚 8（TXD） -> USB-TTL 的 RXD
树莓派物理引脚 6（GND） -> USB-TTL 的 GND
```

USB-TTL 插入电脑后，可使用普通串口助手设置 `115200 / 8-N-1 / HEX显示`。
由于数据是二进制协议，推荐使用项目自带的专用接收工具，它会自动完成帧头
同步、CRC 校验和字段解码：

```powershell
cd E:\gowin\ling_shu_vision
python -m scripts.windows_serial_receiver --port COM5
```

将 `COM5` 换成设备管理器或串口列表中实际出现的端口。未插 USB-TTL 时运行
工具会明确提示 `No COM port detected`。

## 7. 当前未完成的板级事项

软件、串口协议和通用 RTL 已完成。由于当前没有提供所用 FPGA 板卡的具体
UART/电机/编码器管脚和 ToF 型号，仍需在最终板卡工程中完成以下板级工作：

1. 在 `.cst` 约束中绑定时钟、`pi_uart_rx_i`、四路编码器、PWM、方向和急停；
2. 按实际 ToF 型号补充 I²C/SPI 适配器，并输出 `tof_distance_mm_i/tof_valid_i`；
3. 按 TB6612/ACG720 原理图连接 STBY、刹车和电机方向，必要时在 wrapper 中反相；
4. 用高云综合和时序分析检查目标器件资源，再做真实 TX-RX、编码器和电机联调。

完成后应使用高云综合工具检查时序，并进行真实 TX-RX 线缆的端到端测试。
