# 运动控制代码：手动 ModelSim 仿真说明

这一步只验证 FPGA 内部控制逻辑，**不连接电机、不下板**。目前有四个独立的自检顶层：

- `tb_motion_policy`：视觉、ToF、急停和失联条件如何产生运动命令；
- `tb_wheel_control`：麦轮混控、编码器计数、默认 PI 速度环、PWM/方向输出；
- `tb_four_wheel_pid`：四路速度环同时驱动四路 PWM，验证可选微分和积分防饱和。
- `tb_drive_rearm_guard`：故障立即关断、故障解除后控制周期复位，以及短于时钟周期的故障锁存。

即使四个测试都通过，也**不等于**新驱动板已接好；板级管脚、方向输入和编码器极性仍要按实物确认。

## 1. 自己新建 ModelSim 工程

选择 `File -> New -> Project`，例如取名 `acg720_motion_sim`。加入下面十个现有文件；选择引用原文件即可，不需要复制。前六个以 Verilog 编译，后四个以 SystemVerilog 编译。

| 编译顺序 | 文件（均在 `E:\gowin\ling_shu_vision\fpga`） | 用途 |
| --- | --- | --- |
| 1 | `vision_motion_controller.v` | 安全优先级、搜索、跟随、距离策略 |
| 2 | `mecanum_kinematics.v` | `vx/vy/omega` 到四轮速度 |
| 3 | `encoder_speed.v` | A/B 两相信号到速度计数 |
| 4 | `wheel_pi.v` | 每轮速度闭环；默认 PI，设置 `KD>0` 时为 PID |
| 5 | `motor_pwm_dir.v` | 有符号占空比到 PWM/方向 |
| 6 | `drive_rearm_guard.v` | 故障锁存和安全恢复门控 |
| 7 | `tb_motion_policy.sv` | 第一组自检激励与断言 |
| 8 | `tb_wheel_control.sv` | 第二组自检激励与断言 |
| 9 | `tb_four_wheel_pid.sv` | 四路 PID/PWM 联合自检 |
| 10 | `tb_drive_rearm_guard.sv` | 安全恢复自检 |

执行 `Compile -> Compile All`。这里**不用加入** `.gprj`、`.cst`、树莓派代码或串口测试平台。不要把之前的 `mux2`、`acg720_uart_bringup` 或 `fpga_robot_core` 选作本次仿真顶层。

## 2. 运行策略测试

在 Transcript 中逐行输入：

```tcl
vsim -voptargs=+acc work.tb_motion_policy
view wave
add wave -r sim:/tb_motion_policy/*
run -all
```

运行结束，Transcript 应出现：

```text
PASS tb_motion_policy: priority, search, confirm, follow, deadbands
```

Wave 中先看 `test_step`、`state_o`、`safe_stop_o`、`vx_cmd_o`、`vy_cmd_o`、`omega_cmd_o`：

| test_step | 状态码 | 期望现象 |
| --- | ---: | --- |
| 1 | 8 | ToF 无效：三轴命令 0，`safe_stop_o=1` |
| 2 | 10 | 急停优先于 ToF 故障 |
| 3 | 7 | 250 mm 硬停车边界 |
| 4 | 9 | 串口/视觉失联停车 |
| 5 | 1 | 无目标：`omega=200`，`vx=vy=0` |
| 6 | 6 | 目标未确认：保持不动 |
| 7 | 4 | 目标偏左、距离 1500 mm：`vx=250, vy=-76` |
| 8 | 2 | 居中后只前进：`vx=250, vy=0` |
| 9 | 3 | 距离合适、目标偏右：`vx=0, vy=76` |
| 10–11 | 5 | 处于死区：运动命令均为 0，但不是故障停车 |

状态在 `control_tick_i` 上升有效的时钟沿才更新。`test_step=8` 开头故意先改变输入、不发控制 tick，确认输出保持旧值；随后再 tick 更新为状态 2。

## 3. 运行轮控测试

先结束上一仿真，再运行第二个顶层：

```tcl
quit -sim
vsim -voptargs=+acc work.tb_wheel_control
view wave
add wave -r sim:/tb_wheel_control/*
run -all
```

运行结束，Transcript 应出现：

```text
PASS tb_wheel_control: mixer, encoder, PI disable, PWM
```

重点看 `test_step` 与信号：

- 1–4：`fl/fr/rl/rr` 分别验证前进、右移、旋转、超限等比例缩放。轮序是前左、前右、后左、后右。
- 5–6：`encoder_a/encoder_b` 经同步后，`position` 先到 `+4` 再回 `0`；每个采样周期的 `speed` 先是 `+4` 再是 `-4`。这里按 A/B 的四倍频边沿计数。
- 7–10：默认 PI 的 `pi_duty` 依次为 `125 -> 87 -> 0 -> 125`。第 9 步禁用时，输出和积分在**下一时钟**清零，不必等下一次控制 tick；重新使能不继承旧积分。
- 11–12：`pwm_duty=+500` 和 `-500` 都是 50% PWM，`direction` 分别为 0 和 1；第 13 步 `pwm_enable=0` 时 `pwm` 立即变 0。测试中的 PWM 周期缩短为 100 拍，只为加快仿真，不是最终硬件频率。

如果 Wave 为空，确认 `vsim` 顶层名与 `add wave` 路径一致，且使用了 `-voptargs=+acc`；然后点 `Zoom Full`。`$finish` 停在 testbench 最后一行是正常结束，**只有两条 PASS 且没有 FAIL/编译错误**才算本步通过。

### 编码器方向修复后的重跑（2026-10-12）

首次运行若在 `test_step=5` 看到 `position=-4, speed=-4`，这是旧版 `encoder_speed.v` 使用 `1'sd1` 造成的：Verilog 的有符号 1 位 `1` 等于 `-1`，因此加法反而减一。源码现已改成 `32'sd1`。**修改源码后必须 `Compile -> Compile All`，再执行 `quit -sim`、`vsim -voptargs=+acc work.tb_wheel_control`、`run -all`；只点 `restart` 不会重新编译修改后的 RTL。**正向序列 `00->01->11->10->00` 应得到 `+4`，反向应得到 `-4`。

`vsim-WLF-5000/5001` 仅表示另一个 ModelSim 进程或仿真占用了 `vsim.wlf`，ModelSim 会自动使用备用波形文件；它不是此处的编码器失败原因。

## 4. 运行四路 PID/PWM 联合测试

修改源码后，先执行 `Compile -> Compile All`；再在 Transcript 中输入：

```tcl
quit -sim
vsim -voptargs=+acc work.tb_four_wheel_pid
view wave
add wave -r sim:/tb_four_wheel_pid/*
run -all
```

预期结果为：

```text
PASS tb_four_wheel_pid: four lanes, derivative, anti-windup, stop, PWM
```

`test_step` 与关键预期：

| 步骤 | 现象 |
| --- | --- |
| 1 | 四路 `duty[0..3]` 为 `125,-125,0,62`；首次使能不产生微分冲击 |
| 2 | 一整个 100 拍 PWM 周期内，高电平拍数为 `12,12,0,6`；只有第 1 号轮方向为负 |
| 3 | `feedback` 变化而无 `control_tick`，占空比保持不变 |
| 4–5 | 测速变化时 D 项短暂修正；测速稳定后 D 项归零 |
| 6 | 第 0 号轮饱和在 `+1000`，其积分停止增长；其他轮不受影响 |
| 7 | 第 0 号轮目标归零，旧占空比和积分清零 |
| 8–9 | 关断使能立即拉低四路 PWM；重新使能不继承旧积分或微分历史 |

本测试为了验证 D 项，单独设置 `KD=2`；`fpga_robot_core` 的 `WHEEL_KD` **仍默认为 0**。编码器量化噪声可能被微分放大，不能因为仿真通过就把 `KD=2` 直接用于实车。

`wheel_pi.v` 文件名和模块名保留以兼容已建好的 ModelSim 工程：它现在是可选 D 项的速度环。PWM 的固定载波频率由 `motor_pwm_dir.v` 产生；PID 调整的是每轮占空比，不是让 PWM 载波本身“更稳”。

## 5. 运行安全恢复测试

先重新 `Compile -> Compile All`，再在 Transcript 逐行输入（不要输入 Markdown 的 ``` 符号）：

```tcl
quit -sim
vsim -voptargs=+acc work.tb_drive_rearm_guard
view wave
add wave -r sim:/tb_drive_rearm_guard/*
run -all
```

应看到 `PASS tb_drive_rearm_guard: immediate stop, delayed rearm, short pulse latch`。波形中 `fault` 拉高后 `allow` 立即变 0；即使短故障脉冲已消失，`allow` 仍保持 0，直到下一次有效 `control_tick` 才变 1。若 `fault` 持续存在，控制 tick 不得重新使能。该测试仅验证逻辑边界，不能替代实板急停电路验证。

完整核心另需把 `uart_rx.v`、`vision_packet_parser.v`、`vision_uart_bridge.v`、`fpga_robot_core.v` 加入工程；这四个独立 testbench 不能替代核心集成仿真。

## 6. 仿真通过后的边界

本组测试没有发送真实 UART 帧，也没有将 `fpga_robot_core` 与新电机驱动板、ToF 传感器或 ACG720 管脚连在一起。现有 `fpga_robot_core` 的 `WHEEL_COUNTS_AT_FULL_SCALE` 默认是 `0`，因此四路电机输出被锁定；必须先按实物编码器与 100 Hz 控制周期标定，再由单独的板级顶层、管脚约束和新驱动接口适配器接入。未经这些步骤，**不要给电机上电**。
