# 任务 1 / 任务 3 传感器前端维护与复现手册

更新时间：2026-10-24  
适用工程：`E:\gowin\ling_shu_vision`  
当前目标板：小梅哥 ACG720，GW5AT-60B

## 1. 已完成内容

### 1.1 IMU（任务 1）

`imu_yahboom_uart.v` 实现了 Yahboom 高精度 IMU 的 UART 接收和姿态角帧校验：

- 8N1，默认 9600 bit/s；
- 帧格式 `55 TYPE D0 D1 D2 D3 D4 D5 D6 D7 CHECKSUM`；
- `TYPE=0x53` 时输出 roll、pitch、yaw 的有符号原始值；
- 校验为前 10 字节累加和低 8 位；
- 丢字节、噪声或错误校验帧不会产生 `angle_valid_o`；
- 角度换算由上层完成：`angle_deg = raw / 32768 × 180`。

协议解析器对应的 Python 版本在 `src/sensors/yahboom_imu.py`，便于树莓派/GUI 与 FPGA 输出交叉核对。

### 1.2 正点原子 ATK-MS53L2M（任务 3）

`tof_ms53l2m_ascii_uart.v` 实现正点原子模块普通回传模式的 ASCII 距离接收：

- 8N1，默认 115200 bit/s；
- 输入如 `800\r\n`，单位为 mm；
- 兼容 `800,signal\r\n`，只取第一个整数距离；
- 40–8000 mm 之外的数据判为无效；
- 每一路使用一个 RX，四路分别接 `tof0_uart_rx_i` 到 `tof3_uart_rx_i`。

`tof_obstacle_guard.v` 使用四路最近有效距离：

| 最近距离 | 动作 | 速度比例 |
|---:|---|---:|
| `>=800 mm` | 正常 | 1000/1000 |
| `500–799 mm` | 预减速 | 500–999/1000 |
| `251–499 mm` | 强制减速 | 100–499/1000 |
| `<=250 mm` | 立即停车 | 0 |
| 全部无效/超时 | 传感器故障安全停车 | 0 |

`sensor_task1_3_core.v` 把 IMU、四路 ToF 和超时保持组合起来。单路 ToF 数据在新帧到达后保持，超过 `TIMEOUT_MS=250` ms 未更新即失效；这避免了传感器短暂断线时继续驱动。

## 2. 仿真复现

在 PowerShell 中执行：

```powershell
cd E:\gowin\ling_shu_vision\fpga\sensors
& 'D:\software\modelism\win64\vsim.exe' -c -do run_modelsim.do
& 'D:\software\modelism\win64\vsim.exe' -c -do run_camera_modelsim.do
```

成功标志：

```text
SENSOR_FRONTEND_PASS
Errors: 0, Warnings: 0
```

摄像头 DVP 像素链路的成功标志为 `OV5640_DVP_PASS`。两条 do 文件分开运行，便于在明日出现 OV5640 时序问题时只定位摄像头链路。

仿真覆盖：

1. IMU 角度帧的正负 16 位数据和校验；
2. ToF 普通 ASCII 距离帧；
3. 四路最近距离的正常、减速、硬停车和全失效安全停车。

Python 协议单元测试：

```powershell
cd E:\gowin\ling_shu_vision
python -m pytest -q tests/test_sensor_protocols.py
```

当前结果：`3 passed`。

## 3. 明日硬件测试顺序

### 3.1 通用安全检查

1. 先关闭电机驱动板 12 V，车轮离地；
2. FPGA 单独供电，先下载 SRAM 诊断位流；
3. 所有传感器与 FPGA 必须共地；
4. IMU 与 ToF 的 TXD 输出确认不超过 FPGA IO 电压；
5. 不把 ToF/IMU 的 VCC 接到电机 12 V；
6. 每次只接一路传感器，确认波形和串口字节后再扩展到四路。

### 3.2 IMU

默认接 UART：IMU TXD → FPGA `imu_uart_rx_i`，IMU GND → FPGA GND，VCC 按模块标注接 3.3–5 V。先使用 9600 8N1，转动传感器，观察 `TYPE=0x53` 帧是否产生有效姿态角。明天硬件确认后再决定最终 ACG720 管脚；不能直接套用其他 GW5AT 板卡约束。

### 3.3 四路 ToF

ATK-MS53L2M 先设为普通回传模式：

- 每个模块 TXD → 对应 FPGA `tofN_uart_rx_i`；
- VCC 使用模块允许的 3.3/5 V，GND 共地；
- 先单路观察 `800\r\n` 类数据；
- 四路同时使用时必须确认四个串口 RX 管脚没有与编码器、蓝牙、摄像头复用。

若实际模块配置为 Modbus，而不是普通回传模式，本 RTL 不会自动生成请求帧；需先用正点原子工具切回普通回传，或另加 Modbus 主机模块。

## 4. OV5640 摄像头（任务 1）

已找到小梅哥 OV5640 例程和用户手册：

`E:\gowin\ling_shu_vision\tmp\ov5640_ch46`

其中已经包含：

- SCCB/I²C 摄像头初始化表；
- DVP `PCLK/VSYNC/HREF/D[7:0]` 采集；
- RGB565 像素拼接；
- DDR3 帧缓存；
- VGA/DVI 显示链路。

资料包还提供 `02_例程源码/GW5AT60K/第46章 OV5640摄像头采集VGA显示屏显示/ch46_ov5640_ddr3_vga.zip`；压缩包内工程 `.gprj` 的目标器件确为 `GW5AT-60B`，但 `.cst` 文件头保留了 `GW5AT-138` 的旧注释，不能仅凭注释判定管脚版本。任务 1 落板前必须逐项对照 ACG720 原理图、实际模块插座和当前其他接线，检查显示、摄像头和控制引脚。尤其该 VGA 例程把 `VGA_rgb[1]` 指向 `E16`，与本次 ToF 的 `E16/P7-23` 诊断接线冲突；**切换到该摄像头位流前，必须先断电并断开 ToF TXD 在 E16 的连接**。完成管脚核对和仿真前，不直接下载显示例程。

模块手册确认：ACM5640-V5 使用 3.3 V 供电，接口包含 `OV_PCLK`、`OV_VSYNC`、`OV_HREF`、`OV_D[7:0]`、`OV_SCL`、`OV_SDA`、`XCLK`、`OV_RESET` 和 `OV_PWDN`。RGB565 每两个 DVP 字节组成一个像素；采集逻辑已经用 `tb_ov5640_dvp_capture.sv` 验证了像素拼接。明天接线后先用彩条/测试图确认 SCCB 初始化，再接 DDR3/VGA 显示，不要一开始就和电机、蓝牙、ToF 合并下载。

2026-10-24 HDMI 单独上板准备：用户已将 OV5640 插入板载摄像头插座并接 HDMI 显示器，驱动板 12 V 关闭、ToF TXD 从 E16 断开。重新运行 `run_camera_modelsim.do`，结果 `OV5640_DVP_PASS`，0 error、0 warning。检查厂家 `GW5AT60K/第47章 OV5640摄像头采集HDMI显示屏显示/ch47_ov5640_ddr3_hdmi.zip`，工程器件是 GW5AT-60B，输出 1280×720；其约束与现有四路电机工程仅共用板载 50 MHz、S0、LED 管脚，没有重用电机 PWM/方向/编码器引脚。摄像头模块手册第 3 页与开发板原理图第 11 页的 2×10 插座均包含 3.3 V、GND、SCCB、DVP、XCLK、RESET/PWDN；仍须在实物上检查插入方向。

仅从该厂家压缩包提取 `impl/pnr/ov5640_ddr3_hdmi.fs` 到 `tmp/ov5640_ch47_test/`，SHA-256：`9C74B007F9AC357CE0DF2EDC47FAE2EB698FAC9DCA2D75B38B6B3F0AD0349C99`。以 `SRAM Program`（索引 2）下载到 GW5AT-60B，返回 `Finished`、Status `0x70026020`、User Code `0x00004B74`；独立 `Read User Code`（索引 73）读回相同值。**未写 Flash。**该例程顶层将 `led[3:0]` 依次分配为 PLL 复位释放、摄像头初始化完成、DDR3 校准完成和 PLL 锁定，约束对应板上 LED3、LED2、LED1、LED0。用户现场反馈 LED0～3 全亮且 HDMI 实时摄像头画面正常，判定为**独立 OV5640→DDR3→HDMI 链路上板通过**；不等于姿态角叠加或与电机系统整合已经通过。

## 5. 与现有运动控制的连接原则

- 任务 2 的四轮闭环仍作为底层执行器，不改动其方向和编码器符号；
- 任务 3 只对“前进速度指令”施加 `tof_speed_scale_permille_o`，左右转向和倒车策略由上层运动模式决定；
- `tof_hard_stop_o` 应直接进入现有电机安全门控，优先级高于蓝牙、树莓派或导航指令；
- IMU 姿态只用于显示和姿态/航向校正，不能在硬件未验证前直接闭合到电机 PID；
- 摄像头负责任务 1 显示和目标识别，树莓派 GUI 可以显示原始图像、roll/pitch/yaw、四路距离、最近距离、减速比例和停车原因。

## 6. 当前未宣称完成的部分

目前已经完成协议级 RTL、四路安全策略和仿真；尚未宣称以下项目已经通过实机：

1. ACG720-60B 最终传感器管脚约束；
2. 明日 IMU 实物的 UART 电平和姿态角方向；
3. 四个 ATK-MS53L2M 的实际输出模式和同时工作；
4. IMU 姿态角与 OV5640 HDMI 画面同屏叠加，以及相应跨时钟域验证；独立 HDMI 实物图像已通过；
5. ToF 停车信号接入现有四轮闭环后的整车制动距离。

这些项目必须按第 3 节逐项实测后，才能写入最终比赛报告的“实测通过”章节。

## 3.4 只有一只 ToF 时的快速实测

已经提供单路临时顶层：

- 顶层：`tof_single_bringup.v`
- 约束：`acg720_tof_single_bringup.cst`
- ToF RX：暂时复用已经核对的蓝牙 RX 管脚 `E16/P7-23`；测试时必须断开蓝牙 TXD，不能两路信号并接；
- USB-UART TX：`M15`；
- S0：`F15`，按下可复位；
- 串口：115200，8N1，输出 `D=xxxx`；
- 板上 LED2：心跳；LED3：最近 500 ms 有有效距离；LED4：≤250 mm 停车阈值；LED5：251–799 mm 减速阈值；LED6：当前无有效数据；LED7：最近 500 ms 有帧错误。这里 `led_o[0]` 对应板上 LED2，依次类推。

Gowin 工程需加入以下源文件后综合：

```text
../uart_rx.v
../bluetooth_bringup/uart_tx_echo.v
tof_ms53l2m_ascii_uart.v
tof_single_bringup.v
```

也可以直接打开 `acg720_tof_single_bringup.gprj`；批处理脚本为 `build_tof_single.tcl`，User Code 设为 `0x544F4631`（`TOF1`）。该位流是单路传感器诊断版，不要把它当作最终四轮导航位流。

本次 Gowin V1.9.12.04 综合、布局布线和位流生成已完成，0 warning；资源约为 473 LUT/ALU、207 FF、10 个 IO。位流文件为：

`E:\gowin\ling_shu_vision\fpga\sensors\impl\pnr\acg720_tof_single_bringup.fs`

2026-10-24 修订：有效距离灯和阈值灯现在保持最近一次测距状态，连续 500 ms 没有新帧即转为无效；诊断串口在无效时输出 `D=0000`，不能把旧距离当作实时值。另修复了每行报告结尾可能多发换行的问题。新增 `run_tof_single_modelsim.do`，覆盖 900/700/200 mm、串口报告和失联超时，结果 `TOF_SINGLE_BRINGUP_PASS`，0 error、0 warning。

修订后位流 SHA-256：`0451FEF57B5AE6B80D76A089BF866B8CEBD0E2A61240554AD45403F8CDAB7639`。先用 SRAM 下载验证，确认 `D=xxxx` 稳定后再考虑写 Flash。

2026-10-24 下载记录：电脑最初能识别 FT2CH 下载器但 FPGA 未供电，JTAG 扫描失败；FPGA 供电后扫描到 `GW5AT-60B / ID 0x0001481B`。`SRAM Program and Verify` 的编程阶段完成、User Code 为 `0x544F4631`，但读回阶段提示 `Verify failed of at 0`，**不可记录为读回校验通过**。随后采用 `SRAM Program`（操作索引 2）重新下载，返回 `Finished`、Status Code `0x70026020`；独立 `Read User Code`（索引 73）读回 `0x544F4631`。该结果只能证明 SRAM 下载与版本识别，传感器功能仍须看 LED/串口实测。未写 Flash，原 BTD5 Flash 保持不变。

同日 LED2 未闪烁的实测反馈促使再次检查 RTL：心跳计数器原为 24 位，50 MHz 下无法达到 25,000,000 计数值。已改为 32 位，并在单路仿真中加入宽度断言；仿真再次通过。重新生成并以普通 SRAM Program 下载，返回 `Finished`、User Code `0x544F4631`、Status `0x70026020`。**当前最终 TOF1 位流** SHA-256 为 `1BA30F737473BE8EB59EF8364D557B824B12750537D8EC4085D39C0E0460E241`；上述 `0451...` 是前一版，勿再下载。等待重新观察 LED2 心跳及 ToF 实测。

对照 `ATK-MS53L2M模块用户手册_V1.0.pdf` 第 1–4 页：出厂默认 115200 bit/s、30 Hz、普通回传、最近距离，距离以十进制 ASCII 后接 CR/LF；UART TXD/RXD 信号电平为 3.3 V，模块 VCC 可用 3.3 V 或 5 V（手册推荐 5 V）。因此当前诊断程序的 115200/ASCII 解析匹配**出厂设置**；若模块曾被改为 Modbus 或其他波特率，必须先确认其实际设置，不能把 `D=0000` 直接判作硬件损坏。

先只给 ToF 和 FPGA 供电，打开 XCOM 115200 8N1；看到 `D=xxxx` 且板上 LED3 亮。无目标或断线超过 500 ms 时应显示 `D=0000`、LED6 亮。250 mm 内应为板上 LED4 亮，251–799 mm 为 LED5 亮。本位流**仅用于测距诊断，没有电机输出，不进行整车避障试跑，驱动板 12 V 全程保持关闭**；待测距实物验收后，另行集成电机安全门控并重新仿真。

### 3.5 2026-10-24 原始串口链路复核

此前 ToF 模块未供电，TOF1 的 COM6 输出只有 `D=0000`；这不能证明解析器故障。给模块上电后，为排除模式/波特率问题，另建**只用于诊断**的 `tof_single_raw_probe.v`，把 ToF TXD 原样透传到板载 USB-UART；对应工程、脚本和仿真为 `acg720_tof_single_raw_probe.gprj`、`build_tof_raw_probe.tcl`、`run_tof_raw_probe_modelsim.do`。ModelSim 输出 `TOF_RAW_PROBE_PASS`，0 error、0 warning；Gowin 完成综合与布线，综合提示未使用的格式化串口 TX 被优化掉，符合透传设计。原始透传位流 User Code 为 `0x544F4652`（`TOFR`），SHA-256 为 `950A3D4D971013E34FE158EDA5C96610E57E3EF920D18F7A19063A75258E8535`。

`TOFR` 仅写入 SRAM，下载返回 `Finished`、Status `0x70026020`。电脑 COM6 以 115200 8N1 实际收到连续 `455\r\n`、`456\r\n`、`457\r\n` 等十进制 ASCII 数据，后续读数约 467 mm。这证明此时 ToF 已输出、FPGA E16 输入与 M15/CH340/COM6 输出链路畅通，且当前模块仍是与手册一致的普通 ASCII 回传格式。**这些数字是传感器输出，尚未与卷尺对照，不能宣称测距精度已验证。**

透传后已将 `TOF1`（User Code `0x544F4631`）重新下载至 SRAM，返回 `Finished`、Status `0x70026020`，未写 Flash。当前正在等待 COM6 被 XCOM 释放后读取 `D=xxxx`，以区分先前零值仅由未供电造成，还是解析/状态逻辑仍有问题。原始透传版不控制电机；整个复核过程驱动板 12 V 保持关闭。

又以真实参数 50 MHz/115200 bit/s 对实际捕获格式 `455\r\n`、`467\r\n` 做连续帧仿真，`run_tof_ascii_production_baud.do` 输出 `TOF_ASCII_PRODUCTION_BAUD_PASS`，0 error、0 warning。此项证明 RTL 在该输入格式下应解出两个有效距离，但不能替代重新读 COM6 的实机闭环验证。

用户将平整目标放在约 0.5 m 处后报告：板上 LED2 闪烁，LED3 与 LED5 亮，LED4/6/7 灭；这与“近期收到有效帧、距离位于 251–799 mm、无近距硬停和帧错误”的 TOF1 状态定义一致。用户确认单模块测距可用。判定为**单只 ToF 的供电、串口链路、有效帧与区间 LED 现场通过**。由于 COM6 当时被 XCOM 占用，未由脚本再次读取 TOF1 的 `D=xxxx` 输出；原始透传的 455–467 mm 已实读。约 0.5 m 是摆放估计值，尚未做卷尺误差统计；四路并接、与电机安全门控联动、实际减速/停车距离均仍待测。

## 7. 明日验收记录模板

### 7.0 2026-10-25 IMU 独立上位机验证

Yahboom `YB-MRA02-V1.0` 通过 Type-C/板载 CP2102 接电脑，Windows 识别为 `COM6`；YB_IMU 上位机已显示 3D 姿态模型、roll/pitch/yaw、四元数及加速度/角速度曲线，判定为 **IMU 模块、供电、USB 串口和上位机链路通过**。这一步没有把 Type-C 与 FPGA UART 并接，姿态数据尚未写入整车位流。

最终整合接口固定为：蓝牙继续使用 `E16/P7-23` RX、`D16/P7-24` TX；ToF 必须改用独立 FPGA RX 管脚；IMU 再使用另一根独立 RX 管脚。`acg720_tof_single_bringup.cst` 中的 `E16` 只是单路 ToF 诊断临时分配，不能直接沿用到蓝牙/ToF/IMU 共存版本。

每次只改变一项硬件连接，并在这里记录结果：

| 日期/时间 | 项目 | 配置 | 现象 | 判定 | 备注 |
|---|---|---|---|---|---|
|  | IMU UART | 9600 8N1，单模块 |  | 待测 | 记录 roll/pitch/yaw 静止值 |
|  | ToF-0 | 115200，目标距离 |  | 待测 | 与卷尺距离对照 |
|  | ToF-1 | 115200，目标距离 |  | 待测 | 记录刷新率 |
|  | ToF-2 | 115200，目标距离 |  | 待测 | 记录刷新率 |
|  | ToF-3 | 115200，目标距离 |  | 待测 | 记录刷新率 |
|  | 四路避障 | 目标 800/500/250 mm |  | 待测 | 车轮离地后再落地 |
| 2026-10-24 | OV5640 | 厂家 GW5AT-60B HDMI 位流，SRAM | HDMI 实时画面正常、LED0～3 全亮 | 独立链路通过 | OSD 与统一顶层仍待测 |

## 8. 竞赛展示时的安全优先级

执行器的停机优先级固定为：人工急停 > ToF 硬停车/失效停车 > 编码器闭环失速保护 > 任务控制指令。树莓派、蓝牙和摄像头只产生目标或速度请求，不能绕过 FPGA 的 ToF 安全门控。这样可以把“识别、姿态、测距、控制”分成可独立验收的链路，也便于评委现场复现。

## 9. 2026-10-24 总系统整合设计与真实状态

**竞赛基础任务 1～4 的关键工作链路设计在 FPGA（或板上软核 CPU）内。** 树莓派网页和电脑 GUI 用于目标选取、扩展视觉、遥测与调试，不能替代基础任务的 FPGA 摄像头/姿态显示、运动闭环、硬件避障及导航执行。当前写入 Flash 的四轮蓝牙闭环程序应保留；厂家摄像头演示程序及后续整合版本先只下载到 SRAM。任务 1～6 的完整整合与验收计划见 `../COMPETITION_INTEGRATION_2026_CN.md`。

| 功能 | 当前可引用的证据 | 尚未完成的整合验收 |
|---|---|---|
| 四轮运动 | BTD5 四轮离地闭环、前后左右与松手停实测 | 载地直行/横移、制动距离与持续运行 |
| OV5640 | 厂家 HDMI 例程独立 SRAM 上板，实时画面正常 | 移植到统一工程、角度 OSD 同屏 |
| IMU | UART 姿态帧解析 RTL/仿真 | 实物型号、波特率、帧格式、电平、角度方向及超时现场核对 |
| ATK-MS53L2M | 单路 455～467 mm 原始 UART 数据、距离区间 LED 实测 | 与运动指令联动减速/停车；卷尺对照；额外传感器 |

统一顶层建议分四层，逐层复用已经通过的模块：

```text
OV5640 → SCCB/DVP → DDR3 → disp_driver → 姿态/距离 OSD → HDMI
IMU UART → 校验/时间戳 → roll/pitch/yaw 寄存器 ────────┘
ToF UART → 距离/有效期 → 减速与停车仲裁 → 四轮目标速度/使能
蓝牙/导航请求 → 统一运动命令仲裁 ──────────────┘
                                编码器 → 四路 PI/PWM → 电机驱动
``` 

姿态显示先采用固定位置的 FPGA 字模 OSD：例如左上角显示 `ROLL +012.3`、`PITCH -003.1`、`YAW +087.5` 和 `IMU OK/LOST`。IMU 原始角度若**实物协议确为当前 0x55/0x53 格式**，可用至少 32 位有符号中间量换算为十分之一度 `raw × 1800 / 32768`，正负号独立显示。每个有效帧更新姿态寄存器；超过规定时限不再显示旧角度为实时值，而显示 `LOST`。在 HDMI 视频时钟域用同步快照并只在帧边界更新 OSD 数值，避免一帧内数字撕裂；必须对完整多位姿态字做握手/快照，不能仅对每一位各加两级触发器。OSD 插在 `disp_driver` 与 `dvi_encoder` 之间，不改 DDR3 原始帧缓存。电脑 GUI 可通过板载 UART/蓝牙接收同一组遥测，但**GUI 不是基础任务 1 的唯一姿态显示**。

整合阶段顺序及放行条件：

1. **IMU 单独确认。** 驱动板 12 V 关闭；记录模块具体型号、供电、TX 空闲高电平、实测波特率和至少一组静止/旋转原始帧。若与 9600、`55 53` 不符，先修正解析器及仿真，不把错误角度接入运动控制。
2. **摄像头 + IMU OSD。** 保留已通过的 720p HDMI 摄像头链路，先叠加测试常数和字模，再叠加真实 roll/pitch/yaw 与失联提示；检查画面无闪烁、角度变化方向正确。此阶段电机 12 V 关闭。
3. **ToF + 四轮安全链。** 初期只装一只**车头方向** ToF，配置必需传感器掩码 `0001`。前进时按距离分级减速、≤250 mm 硬停；丢帧/超时也禁止前进。停止条件必须进入 PI 通道 `enable`、目标速度清零和 PWM/方向安全门控，不能只遮住最终 PWM 输出而留下积分和陈旧命令。后退逃离的允许条件需单独定义，不能被前向 ToF 误锁死。额外三只 ToF 到货后再扩大掩码；不能把“只要任一路有效”当作四路全健康。
4. **统一运动顶层。** 将现有蓝牙、导航目标请求仲裁为唯一运动指令，安全优先级为 S0 急停 ＞ ToF 近距/必需路失联 ＞ 编码器故障/通信看门狗 ＞ 蓝牙/导航请求。复位、故障清除后必须先回到中位命令才能重新启动；上电默认停车。逐项做 ModelSim、Gowin 综合/布局布线/时序及管脚冲突检查。
5. **先 SRAM 上板、后考虑 Flash。** 先断开驱动板 12 V 验证摄像头/IMU/ToF/遥测；再四轮离地验证减速和自动停车，最后在空旷地面低速测制动距离。记录整合位流的 SHA-256、User Code、仿真标志、时序报告和现场数据。只有整合版完成这些验收，才考虑替换当前 Flash 中可回退的 BTD5。

**管脚注意：** 本次单路 ToF 临时占用 `E16/P7-23`，它原是蓝牙 TXD→FPGA RX 的输入；正式整合时必须为 ToF、蓝牙、IMU 分配互不冲突的 RX，引脚电平均核对为 FPGA 可接受的 3.3 V，不能把两只模块 TXD 并接。专用摄像头插座与 HDMI 的实际约束仍须与四轮工程合并后重新检查，不可仅凭各自独立位流成功就推断整合版可用。

本次软件复核：`python -m pytest -q tests/test_sensor_protocols.py` 为 `3 passed`。整合版在独立 ModelSim 库中重新运行了 `SENSOR_FRONTEND_PASS`、`PASS tb_acg720_sensor_gate` 和 `PASS tb_acg720_motor_bt_nav`，均为 0 error、0 warning；没有删除原 sensors/work 锁文件。

## 10. SIN1 统一导航位流（2026-10-25）

根据 ACG720 资料包中的 P7 原理图和管脚表，已将 IMU 与单路 ToF 接入 BTD6 导航顶层：

- `IMU_RX=B17/GPIO0_22/P7-23`；
- `TOF0_RX=B18/GPIO0_23/P7-24`；
- 蓝牙仍使用 `E16/D16`，不与 IMU/ToF 共用；
- `sensor_task1_3_core` 增加 `TOF_COUNT` 参数，SIN1 只综合一只 ToF，避免未接三路产生无意义逻辑；
- `tof_hard_stop` 进入电机使能门控，ToF 超时和无效数据均停车；
- SIN1 位流：`output/board/SIN1_btd6_imu_tof_nav_2026-10-25.fs`，User Code `0x53494E31`，SHA-256 `424F2E50AB237EBAA9FEBE4818110E8C578CBCEC5EBAC7803DB81C96670B421B`。
- 板载 USB-UART（M15）以 115200 8N1 输出 `I1 T1 Dxxxx H0` 状态行；复位释放后立即发首帧，之后约 250 ms 周期发送。若 COM6 无数据，优先核对 USB-UART 线、COM 号和 M15/板载串口链路，不要把 IMU/ToF TX 并接到蓝牙 RX。

SIN1 已完成 SRAM Program；现场首先应验证 ToF 有效帧使 LED7 熄灭、IMU 有效姿态帧使 LED5 亮，然后再在四轮离地条件下验证蓝牙/导航运动。该位流未写 Flash。
