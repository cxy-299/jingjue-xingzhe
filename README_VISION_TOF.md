# 灵枢智行：视觉左右对位 + ToF前后距离

这一版把控制职责正式拆开：

```text
Camera + YOLO
    │
    ├─ cx / 视觉横向误差
    │
    └─ vy_ref
          ↓
      ACG720 / 模拟FPGA
          ↑
        ToF距离
          │
          └─ vx
```

## 核心原则

### 视觉负责左右

```text
目标偏左  -> vy < 0
目标居中  -> vy = 0
目标偏右  -> vy > 0
```

视觉不再根据 bbox 面积判断前后距离。

### ToF负责前后

默认参数：

```text
目标距离：500 mm
距离死区：±50 mm
硬停车：250 mm
```

例如：

```text
1500 mm -> vx > 0，向前接近
900  mm -> vx > 0，但速度降低
550  mm -> vx = 0
200  mm -> HARD_STOP
ToF无效 -> TOF_FAULT，全部运动清零
```

---

# 如何测试

## 窗口1：模拟FPGA + 模拟ToF

```powershell
cd E:\gowin\ling_shu_vision
.\.venv\Scripts\python.exe -m scripts.mock_fpga_receiver
```

按键：

```text
S = 模拟靠近目标，ToF距离减少100 mm
W = 模拟远离目标，ToF距离增加100 mm
I = 模拟ToF失效/恢复
R = 重置ToF距离
Q = 退出
```

## 窗口2：视觉程序

```powershell
cd E:\gowin\ling_shu_vision
.\.venv\Scripts\python.exe -m src.main --config config\config.yaml
```

---

# 推荐测试

1. 人站画面左侧，ToF=1500 mm：

```text
Vision : ALIGN_LEFT
ToF    : 1500 mm
Output : vx>0, vy<0
Action : APPROACH_LEFT
```

2. 人移到正中：

```text
vx>0, vy≈0
Action : APPROACH
```

3. 在窗口1连续按 S，让距离到 500~550 mm：

```text
vx=0
```

如果人仍偏左：

```text
vy<0
Action : ALIGN_LEFT
```

说明“前后停止，但仍能做左右精对位”。

4. 目标居中、距离合适：

```text
vx=0
vy=0
Action=STOP
```

5. 按 I 模拟 ToF 故障：

```text
TOF_FAULT
vx=0
vy=0
omega=0
```

这是未来实车应该保留的安全策略。

---

# 实车迁移

电脑阶段：

```text
视觉PC -> UDP -> 模拟FPGA + MockToF
```

实车阶段：

```text
Raspberry Pi
Camera3 + YOLO
        │ UART
        ↓
ACG720
  ├─ 接收视觉 cx / vy_ref
  ├─ 本地读取 ToF
  ├─ 计算 vx
  ├─ 安全检查
  ├─ 麦轮运动学
  └─ 四轮 PID / PWM
```

因此最终**树莓派不决定前进距离，也不直接控制电机**。
