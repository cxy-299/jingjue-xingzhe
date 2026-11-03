# FPGA 视觉串口与运动控制核心

这组 RTL 现在包含从树莓派视觉串口到四路电机 PWM 的板卡无关控制核心。树莓派
只发送目标方位和置信度，FPGA 负责失联保护、ToF 前后距离策略、麦轮运动学、
编码器测速、四路可选 D 项的速度环和 PWM/方向输出。

## 文件

- `uart_rx.v`：115200 baud、8-N-1 UART 接收；
- `vision_packet_parser.v`：帧同步、长度检查、CRC16-CCITT 和字段解析；
- `vision_uart_bridge.v`：整合 UART、解析器和 1500 ms 失联看门狗。
- `vision_motion_controller.v`：视觉横向对位 + ToF 前向接近 + 急停/失联安全策略；
- `mecanum_kinematics.v`：将 `vx/vy/omega` 分解为四个轮速指令；
- `encoder_speed.v`：同步正交编码器计数，并按控制周期输出计数增量；
- `wheel_pi.v`：四路整数速度环，默认 PI，可配置 D 项并带积分防饱和；
- `motor_pwm_dir.v`：有符号占空比转换为 PWM 和方向；
- `drive_rearm_guard.v`：故障组合关断并锁存，解除后在控制周期重新放行；
- `fpga_robot_core.v`：上述模块的完整例化入口。
- `tb_motion_controller.v`：策略层的 Verilog-2001 冒烟仿真用例。
- `tb_motion_policy.sv`：策略层完整自检，覆盖故障优先级、目标确认与死区。
- `tb_wheel_control.sv`：运动学、编码器、PI 和 PWM 的独立自检。
- `tb_four_wheel_pid.sv`：四路速度环到四路 PWM 的联合自检（测试内开启 D 项）。
- `tb_drive_rearm_guard.sv`：短故障脉冲、恢复时序自检。
- `MOTION_MODELSIM_MANUAL_CN.md`：在 ModelSim 新建工程、看波形的中文步骤。
- `BLUETOOTH_CONTROL_PLAN_CN.md`：未来手机手动驾驶及在线 PID 调参的接口与安全规则。

在最终高云工程中例化 `fpga_robot_core`，按实际开发板时钟修改 `CLK_HZ`。默认
值为 50 MHz，控制周期为 100 Hz，PWM 为 20 kHz。将 `pi_uart_rx_i` 约束到
FPGA 的 3.3V UART RX 引脚，将四路编码器 A/B 和电机 PWM/方向连接到实际管脚。

`tof_distance_mm_i` 和 `tof_valid_i` 是传感器适配边界：可以由板上的 ToF I²C/SPI
控制器、软核驱动或外部传感器 MCU 提供。由于当前没有给出 ToF 型号、地址和
ACG720 管脚约束，本目录不虚构具体 I²C 时序；接入适配器后即可直接连接本核心。

## 控制单位和默认策略

所有运动命令使用整数 milli-unit，`1000` 表示归一化速度 `1.000`。默认策略与
电脑端 ToF/视觉模型一致：目标距离 500 mm，±50 mm 死区，250 mm 硬停车；
视觉中心误差在 ±800/10000 内认为居中，搜索时只原地旋转，不允许前进。

安全优先级为：急停 > ToF 无效/硬停车 > UART 失联 > 目标确认 > 正常跟随。
`safe_stop_o=1` 时四路 PWM 被关闭，`link_alive_o=0` 时所有运动命令归零。

## 推荐综合文件顺序

```text
uart_rx.v
vision_packet_parser.v
vision_uart_bridge.v
vision_motion_controller.v
mecanum_kinematics.v
encoder_speed.v
wheel_pi.v
motor_pwm_dir.v
drive_rearm_guard.v
fpga_robot_core.v
```

手动 ModelSim 仿真先按 [运动控制测试说明](MOTION_MODELSIM_MANUAL_CN.md)
分别运行 `tb_motion_policy`、`tb_wheel_control`、`tb_four_wheel_pid` 和
`tb_drive_rearm_guard`，要求四条 PASS。旧的
`tb_motion_controller.v` 仅保留为轻量冒烟测试。单元测试不能代替真实 UART
到四轮输出的集成验收，也不能代替板级管脚与驱动板接线验证。

顶层约束和新电机驱动器的使能/刹车接口仍需在具体 ACG720 工程中补充。电机方向若
与机械安装方向相反，应在板级 wrapper 中对对应 `motor_dir_o[n]` 或编码器极性
做单独反相，不要改动协议和安全逻辑。

## 安全接口

- `link_alive_o=0`：超过 1500 ms 没有合法视觉包/心跳，电机必须停车；
- `target_valid_o=0`：没有检测到目标，不允许前进；
- `target_confirmed_o=0`：目标尚未通过连续帧确认，不允许开始跟随；
- `vision_packet_pulse_o`：收到一帧 CRC 正确的视觉结果时产生单周期脉冲；
- `crc_error_count_o`：可接数码管或调试寄存器，用于现场排查线路干扰。

`wheel_pi.v` 在 `enable_i=0` 后下一时钟清除占空比和积分，避免故障解除后
短暂恢复旧输出；`motor_pwm_dir.v` 的 `enable_i=0` 则直接组合关断 PWM。
顶层 `safe_stop_o` 由故障恢复门控产生：急停、ToF 无效、硬停车或失联立即停车，
故障消失后还须等一个控制周期才允许重新启动。短于时钟周期的故障也被锁存。

四路 PWM 已各自接在编码器速度环之后。`fpga_robot_core` 的 `WHEEL_KP/KI/KD`
以及 `WHEEL_PID_SHIFT` 可调，`WHEEL_KD=0` 为保守默认值；要启用微分，先实测
编码器计数噪声、电机转向与阶跃响应，再逐步调参。零速目标在下一个控制周期清除
该轮积分与占空比；故障使能则不等待控制周期，组合关断 PWM。新驱动板接口尚未
确定，本目录没有写死旧板的 `IN1/IN2/PWM` 管脚关系。

所有归一化坐标和置信度均为 `0..10000`。`center_error_o` 为有符号
`-10000..10000`，负数表示目标在画面左侧，正数表示在右侧。
