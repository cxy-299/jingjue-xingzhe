# BTD5 蓝牙四轮闭环维护与复现手册

最后更新：2026-10-24（亚洲/上海）  
工程目录：`E:\gowin\ling_shu_vision\fpga\motor_bt_drive`

## 1. 当前可复现版本

| 项目 | 当前值 |
|---|---|
| FPGA | Gowin GW5AT-60B（板卡 ACG720-GW5AT60） |
| 位流 | `impl/pnr/acg720_motor_bt_drive.fs` |
| 用户码 | `0x42544435`（BTD5） |
| 位流 SHA-256 | `E292132B9363492BCEEF198E7BA65C3929F3D40B9E18930D43A1070A3C8DF210` |
| FPGA 时钟 | 50 MHz |
| 蓝牙命令 | ZS-040，9600/8N1，ASCII `F/B/L/R/S` 与 `1/2/3` |
| 蓝牙回传 | FPGA D16/P7-24 → 模块 RXD，9600/8N1，约每 250 ms 输出 M1～M4 诊断帧 |
| 板载诊断口 | CH340，COM6，115200/8N1，保留作备用 |
| Windows 蓝牙口 | 通常为 COM9；以设备管理器实际枚举为准 |

BTD5 相比 BTD4 增加了第二路 9600 波特率诊断发送器：蓝牙模块可直接把编码器闭环状态回传到 GUI，COM6 不再是日常遥控必需品。电机 PWM、方向、安全门控和 BTD4 的复位锁停逻辑保持不变。

## 2. 安全前置条件

1. 写 SRAM、写 Flash、改线前：驱动板 12 V 关闭；四轮离地；S1 松开。
2. FPGA 可保持供电，JTAG 下载器接在电脑；不要在带电状态插拔电机、编码器、蓝牙或电平转换器线。
3. 编码器输出约 5 V 时必须经过 TXS0108E：编码器侧接 B 侧（1.65～5.5 V），FPGA 侧接 A 侧（1.2～3.6 V），VA=3.3 V、VB=5 V、OE 接低电平侧允许的高电平，模块 GND 与 FPGA/驱动板共地。
4. ZS-040 使用 3.3 V 供电时，模块 TXD 空闲高电平必须实测不超过 3.3 V；TXD→FPGA P7-23/E16，FPGA TX→模块 RXD 为 P7-24/D16，GND 共地。不要把 5 V 或 12 V 送入 FPGA GPIO。
5. 首次落地前只允许低速、短时、可立即断电的测试；离地验证通过不等于地面运动、横移精度或定位精度已经通过。

## 3. 从源码重新仿真与构建

在 PowerShell 中：

```powershell
Set-Location E:\gowin\ling_shu_vision\fpga\motor_bt_drive

# ModelSim 回归
D:\software\modelism\win64\vsim.exe -c -do run_modelsim.do

# Gowin 综合、布局布线、时序与 FS 输出
D:\software\gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe build.tcl

# 校验生成位流
Get-FileHash .\impl\pnr\acg720_motor_bt_drive.fs -Algorithm SHA256
```

BTD5 本次结果：ModelSim 编译错误 0、警告 0，回归覆盖 F/B/L/R、档位、四路反馈、停止优先级、看门狗、S0、帧错误和运行限时；Gowin 实际 Fmax 63.187 MHz，建立/保持违例端点 0，逻辑约 4636/59904、寄存器约 1046/60780、I/O 31/297。

## 4. 下载 SRAM（首次验证，断电会丢失）

确保第 2 节安全条件满足后执行：

```powershell
$fs = 'E:\gowin\ling_shu_vision\fpga\motor_bt_drive\impl\pnr\acg720_motor_bt_drive.fs'
D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe `
  --device GW5AT-60B --operation_index 2 --fsFile $fs `
  --cable-index 1 --frequency 2.5MHz
```

成功标志：`User Code is: 0x42544435`、`Status Code is: 0x70026020`、`Finished.`。上电初态应为 LED2 闪烁、LED3 常亮、LED4～LED7 熄灭，四轮静止。

## 5. 写入外部 Flash（本次已经完成）

只有 SRAM 版已经验证后才执行。该操作会擦除并覆盖外部 Flash 中的旧启动镜像：

```powershell
$fs = 'E:\gowin\ling_shu_vision\fpga\motor_bt_drive\impl\pnr\acg720_motor_bt_drive.fs'
D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe `
  --device GW5AT-60B --operation_index 54 --fsFile $fs `
  --cable-index 1 --frequency 2.5MHz
```

独立校验（本次已执行并成功）：

```powershell
$log = 'E:\gowin\ling_shu_vision\fpga\motor_bt_drive\impl\pnr\btd5_flash_verify_20261024.log'
D:\software\gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe `
  --device GW5AT-60B --operation_index 66 --fsFile $fs `
  --cable-index 1 --frequency 2.5MHz *> $log
Get-Content $log -Tail 10
```

本次校验末尾为 `Verify Flash successfully.`、`Finished.`，耗时约 13.77 s；芯片外部 Flash ID 为 `0xC22018`。写入完成后若要验证断电启动：先关闭 12 V，断开 FPGA 供电，重新上电，确认 LED2/LED3 初态，再恢复蓝牙与电机测试。

## 6. Windows 蓝牙 GUI

GUI 文件仍保存在 `pc_bt_control_btd4.py`（窗口标题已标为 BTD5-TX，以保持旧启动脚本兼容）。启动：

```powershell
Set-Location E:\gowin\ling_shu_vision\fpga\motor_bt_drive
python .\pc_bt_control_btd4.py --port COM9
```

若 COM9 变化，先在设备管理器或 `Get-CimInstance Win32_SerialPort` 查实际端口。XCOM 不得同时占用 COM9；COM6 可用于独立诊断，但不是 BTD5 蓝牙回传的必需端口。

GUI 使用顺序：

1. 连接 COM9，确认顶部显示“COM 已打开 · TX 正常”。
2. 确认“允许离地试转”默认未勾选；先观察“蓝牙回传”栏是否出现 `M1 T...`。无电机动作也应能收到周期帧，前提是 FPGA D16→蓝牙 RXD 线已接好。
3. 离地测试时才勾选试转；按住 F/B/L/R，松开即停止。速度档先发停止，再选择 1/2/3。
4. GUI 显示的是蓝牙收到的最新编码器诊断行；FPGA 没有 ACK，不能把“COM 已打开”当作 FPGA 已收到命令。
5. 写入故障、超时或部分写入时 GUI 会自动断开并撤销试转许可；先关闭 12 V，再排查 COM 占用、供电和接线。

## 7. 已完成实测与尚待记录

- 已完成：Windows COM9 经典蓝牙连通；BTD4/BTD5 前进离地四轮同向、松开全停、LED7 熄灭；后退、左横移、右横移离地轮向与安全停机初步通过。
- 已完成：BTD5 SRAM 下载、用户码核对、Flash 写入与独立校验。
- 待记录：断电后由 Flash 自动启动的 LED 初态；蓝牙 COM9 实际收到连续 `M1～M4` 回传；接地后的低速前后左右、启动同步、编码器误差和 PID 参数。
- 禁止直接宣称：离地轮向不等于地面轨迹；没有 ToF/IMU/地图闭环的测试记录，不得宣称自主导航通过。

## 8. 回滚与故障处理

- SRAM 临时验证：重新下载已知可用的 `.fs` 即可；断电后 SRAM 内容消失。
- Flash 回滚：使用已保存的 BTD4 或其他已验证 `.fs`，先 SRAM 验证，再按第 5 节操作 54/66 写回 Flash。
- LED7 亮、安全锁停或电机持续转：立即关闭驱动板 12 V，保持轮子离地，保留 GUI 日志、COM6 诊断和 LED 状态；不要连续重启或反复按方向键。
- COM9 无回传：先确认蓝牙模块已连接、FPGA D16/P7-24→模块 RXD、共地和 3.3 V 电平；再用 COM6 检查 FPGA 是否仍在输出诊断。无回传时不影响 COM6 备用诊断，但不要把 GUI 的发送状态当作接收证据。
