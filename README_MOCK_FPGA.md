# 电脑模拟 FPGA 接收端

这一版在现有“视觉模拟决策版”基础上增加了一个**独立的 PC 模拟 FPGA 接收端**。

## 为什么用 UDP？

你现在没有连接 ACG720，因此 Windows 上需要一种方式让“视觉程序”和“模拟 FPGA”成为两个独立进程。

这里使用：

```text
127.0.0.1:9999 UDP
```

只作为“虚拟串口线”。

**UDP 内部发送的字节就是正式协议帧本身：**

```text
AA 55 | VERSION | TYPE | SEQ | LEN | PAYLOAD | CRC16
```

所以未来换成 UART 时，`protocol.py` 和数据结构不需要推倒重来，只需将传输层由 `UdpLink` 换为 `SerialLink`。

---

## 运行方法

### PowerShell 1：启动模拟 FPGA

进入项目：

```powershell
cd E:\gowin\ling_shu_vision
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
python -m scripts.mock_fpga_receiver
```

正常显示：

```text
灵枢智行 - PC模拟 FPGA 接收端
UDP listening: 127.0.0.1:9999
```

### PowerShell 2：启动视觉主程序

```powershell
cd E:\gowin\ling_shu_vision
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
python -m src.main --config config\config.yaml
```

主程序会显示：

```text
[MOCK FPGA] ON 127.0.0.1:9999
```

---

## 预期现象

当人在画面中央且较远：

```text
[RX VISION] CRC=OK
  action     : APPROACH (0x04)
  confidence : 93.1%
  cx / cy    : 5030 / 4870
  target_side: CENTER
```

人偏左：

```text
action : ALIGN_LEFT (0x02)
```

人偏右：

```text
action : ALIGN_RIGHT (0x03)
```

靠近：

```text
action : STOP (0x05)
```

离开画面：

```text
action : SEARCH (0x01)
```

---

## 当前动作编号

```text
0x00 IDLE
0x01 SEARCH
0x02 ALIGN_LEFT
0x03 ALIGN_RIGHT
0x04 APPROACH
0x05 STOP
0x06 HOLD
0x07 TARGET_LOST
0xFF ERROR
```

---

## 接收端还会检查

- 帧头
- 长度
- CRC16-CCITT
- 序号连续性
- 心跳
- 超时

如果超过 1 s 没有收到数据，会出现：

```text
[WATCHDOG] >1.0 s 未收到视觉数据 -> 实机应进入安全状态
```

这正是后面 FPGA 看门狗应该实现的行为。

---

## 一个重要原则

视觉端发送的是：

```text
目标有效性
动作意图
class_id
confidence
cx/cy/w/h
frame_id
```

而不是 PWM。

真实 ACG720 仍然负责：

```text
ToF安全检查
急停
通信超时
麦轮运动学
轮速PID
PWM
```

因此即使 AI 误识别，视觉端也不能绕过 FPGA 的安全控制。
