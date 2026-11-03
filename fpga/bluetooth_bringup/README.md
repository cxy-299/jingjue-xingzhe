# ZS-040 蓝牙模块独立串口回显验收

本工程是**隔离诊断位流**，不是手机遥控、PID 调参或自动导航位流。它从 P7-23 接收 9600 baud、8-N-1 UART 字节，并从 P7-24 原样回传。已在顶层把四路电机的 PWM、IN1、IN2 共 12 个输出固定为低。烧入 SRAM 会覆盖此前的导航/四轮位流；断电后 SRAM 位流也会丢失。

## 上板前的电气检查

照片上该模块的背面标为 ZS-040；**排针朝下、从背面看**，六针从左到右为 `EN, VCC, GND, TXD, RXD, STATE`。ZS-040 只是底板标识，不能单凭它确认内部固件、默认波特率或手机兼容性。EN 和 STATE 此次留空。

1. 关闭驱动板 **12 V**，车轮离地；不要接入未经验证的 5 V 编码器信号，也不要带电插拔。先给蓝牙模块单独上电，确认其 VCC 供电规格；常见 ZS-040 带稳压器的版本使用约 5 V，但**不能假定手中变体一定相同**。优先使用可限流的稳压电源，不要把 5 V 接进 FPGA GPIO。
2. 用万用表以模块 GND 为参考，量模块 **TXD 空闲高电平**。只有确认其输出不高于 FPGA 3.3 V 输入允许范围后，才能把 TXD 接 P7-23。若测到约 5 V，必须先降到 3.3 V，不能直连。
3. FPGA 和模块 GND 必须共地；若模块和 FPGA 分别供电，还要避免一方断电而另一方经 UART 信号线反向供电。确认断电后再连线，上电后再复测 TXD 电平。

| 模块丝印 | 连接 | 备注 |
| --- | --- | --- |
| GND | FPGA P7-30 GND | 与模块电源负极相通。 |
| TXD | FPGA P7-23，E16 | 先测得约 3.3 V 空闲高电平，再连接。 |
| RXD | FPGA P7-24，D16 | FPGA 3.3 V UART TX；建议先做单向接收，再连接此线测试回显。 |
| VCC | 经实测规格确认的模块电源 | 不是 FPGA GPIO；供电来源及电流能力须核对。 |
| EN、STATE | 不连接 | 当前验收不使用。 |

OV5640 使用独立 P4 摄像头接口，与本工程的 P7-23/24 物理引脚无冲突；**此诊断位流不驱动摄像头**。树莓派原有板载 CH340 串口也不与 P7-23/24 并线。

## 下载和观察

ModelSim 逻辑仿真：`& 'D:\software\modelism\win64\vsim.exe' -c -do run_modelsim.do`。

### 2026-10-23 外部 Flash 尝试记录

- 用户报告模块使用 3.3 V 供电，RXD/TXD 电平约 3.3 V；随后确认四线已接入 FPGA。驱动板 12 V 报告为关闭。注意：照片中的 `ZS-040` 是载板标识，不能据此确认核心蓝牙协议或此块载板的 VCC 最低工作电压。
- JTAG 只读扫描识别 `GW5AT-60B`（ID `0x0001481B`），`exFlash Detect ID` 读到 `0xC22018`。回显位流 SHA-256 与下文记录一致，ModelSim 重新运行通过。
- `exFlash Erase,Program,Verify`（CLI 操作 9）报 `spi flash not found`；改用手册中 GW5AT 对应的 `exFlash Erase,Program,Verify Arora V`（操作 54）报 `Gowin Device not found`。其后的只读 JTAG 扫描找不到目标，状态寄存器返回 `0xFFFFFFFF`。
- **两次操作均未报告擦除、写入或校验成功；不能宣称 Flash 已更新。**在现场确认 FPGA 供电、下载器及 JTAG 恢复前，不再执行任何烧录操作。电机遥控位流更未写入 Flash。
- 开发板断电再上电后 JTAG 重新识别。回显位流已执行一次 `SRAM Program and Verify`，下载器返回版本码 `0x42543031`、状态 `0x70026020`，但同时报 `Verify failed at 0`；因此**未确认 SRAM 回读校验通过**。用户随后确认 LED2 闪烁、LED3 常亮、LED4～7 灭，这只能证明诊断逻辑在运行，尚未证明无线连接或 UART 回显。驱动板 12 V 保持关闭。

- ModelSim 2020.4：快速参数和实际 `50 MHz/9600 baud` 参数均 `PASS tb_acg720_bt_echo`，覆盖 RX、TX 回显、帧错误、复位、电机输出恒低；两次编译和仿真均 0 errors、0 warnings。
- Gowin V1.9.12.04：综合、布局布线、位流生成成功；50 MHz 约束下 Actual Fmax 176.876 MHz；setup/hold TNS 均为 0，违例端点均为 0。
- 位流 SHA-256：`D245657EEE50BD576F65137BAE7F2DC8243F5AC5318273C711D1BD42227CA6AC`。
- 用户报告模块 VCC、TXD/RXD 约 3.3 V，设备名已设为 `cxy`，UART 为 9600；这些尚需在模块实际运行时复测。用户使用江协科技的微信蓝牙串口小程序未扫描到该模块；Windows/Android 经典蓝牙扫描、模块实际协议和 UART 回显均未验收。不可将离线 PASS 或 LED 初态记为蓝牙上板通过。

### 2026-10-23 断电后的离线诊断与下次上板顺序

- 用户已断电。**SRAM 诊断位流会随 FPGA 断电丢失**；下次测试须重新下载安全回显位流。不要假定 Flash 已写入，不要在驱动板 12 V 开启时诊断蓝牙。
- 江协科技官方[手机蓝牙控制说明](https://jiangxiekeji.com/problem/phc-1.html)指定小程序连接 `HC-04BLE`。如果手头模块的核心是经典蓝牙 SPP/HC-05 一类，微信 BLE 扫描不显示它是协议不匹配，并非 FPGA UART 9600 波特率、蓝牙名称或 PWM 逻辑问题。这仍是**待证实推断**，因为 `ZS-040` 载板可搭配不同核心模块。
- 另一个待排查原因是载板供电：某些带稳压器的 ZS-040 变体从 VCC 接 3.3 V 会使核心欠压。不可仅凭外观改接 5 V；先核对该实物卖家的供电规格，隔离 FPGA UART 后用符合规格的限流电源单独供电，观察指示灯并测 VCC。任何提高 VCC 的尝试都要重新测 TXD 空闲高电平，不得把 5 V 直接送入 FPGA GPIO。
- 下次按顺序验证：① 12 V 关闭、四轮离地、断电拆开蓝牙与 FPGA UART；② 单独给蓝牙模块按已核实规格供电，观察指示灯，测实际 VCC；③ 用 Windows“添加蓝牙设备”或 Android 经典蓝牙扫描 `cxy`，并记录手机小程序是否仍不可见；④ 若经典蓝牙可见，先确认 TXD ≤3.3 V、共地，再重新下载安全回显 SRAM 位流，连接串口测试 ASCII `A` 的 LED6 和回显；⑤ 只有回显、失联停机和电机安全验证完成后，才考虑遥控位流。全过程不依赖电机 12 V。
- 若必须使用江协科技微信小程序，应选与其兼容、已验证 UART 电平的 BLE 串口模块，并将小程序按键发送内容与 FPGA 指令协议逐项核对；不能把经典 SPP 模块改名为 `cxy` 就当作 BLE 模块使用。
- 本次在 ModelSim 2020.4 重新执行 `run_modelsim_9600.do`，`50 MHz/9600 baud` 测试输出 `PASS tb_acg720_bt_echo`；编译 0 errors、0 warnings。仿真覆盖接收、回显、帧错误、复位和全部电机输出低。

### 2026-10-24 供电选择与重新下载

- ACG720 原理图的 S5（USB/DC）只是在板载 DC 降压 5 V `OUTPUT_5V` 与 USB 串口 5 V `USB_UART_VBUS` 之间选择 `VCC5V0` 电源，不是配置存储器模式开关。使用 DC 插座供电时可保持 DC；不可带电改拨。
- 原理图列出外部 QSPI Flash U3 `MX25L12845G`，板卡第 2 章教程给出 `External Flash Mode 5A`、`exFlash Erase,Program 5A`、`Generic Flash`、地址 `0x000000` 的固化流程。高云 60K 配置文档说明 `MODE[2:0]=001` 为上电从外部 Flash 加载的 MSPI，JTAG 与 MODE 输入无关。上次 Flash 下载失败不代表硬件不支持，但尚未确认失败原因；不要误称 Flash 已写入。
- 用户确认 FPGA 供电、驱动板 12 V 关闭、四轮离地后，JTAG 只读扫描识别 ID `0x0001481B`。电机 PWM/IN1/IN2 全低的 `acg720_bt_echo.fs` 以 `SRAM Program` 重新下载；下载器输出 `User Code 0x42543031`、`Status 0x70026020`、`Finished`。这次没有执行读回校验，也没有写入 Flash；断电仍会丢失诊断位流。
- Windows 已配对 `cxy`，其蓝牙 SPP 对应 COM9（COM8 为另一蓝牙虚拟口，COM6 为 USB CH340）。尝试从 COM9 发送 `A` 时打开端口返回 `Access denied`，同时电脑上运行着 XCOM V2.6；需先确认 XCOM 是否占用 COM9，不能算蓝牙 UART 回显已通过。
- Flash 固化前需明确要固化的最终位流，并知晓会覆盖现有的掉电启动镜像。诊断回显位流不含蓝牙运动控制；不要为省去 SRAM 下载而把它误当成最终遥控程序。先完成回显与失联停车验证，再决定安全的 Flash 固化目标和备份策略。
- 用户关闭 XCOM 占用后，Windows COM9 以 `9600,8N1` 依次发送 `A`、`B`、`A`，分别收到 `0x41/A`、`0x42/B`、`0x41/A`。因此 Windows SPP→蓝牙模块→FPGA UART RX→FPGA UART TX→蓝牙模块→Windows 的双向链路已在安全回显位流下实测通过；这仍不等于蓝牙运动控制位流已实现或上板通过。
