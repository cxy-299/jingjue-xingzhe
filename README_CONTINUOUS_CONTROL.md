# 灵枢智行：边对位、边接近连续控制版

这一版将旧的“先对准，再前进”离散状态机升级为适合麦克纳姆底盘的连续视觉控制。

## 1. 核心变化

旧版：

```text
偏左 -> ALIGN_LEFT，vx=0
居中 -> APPROACH，vx>0
```

新版：

```text
偏左且较远 -> APPROACH_LEFT
vx > 0，同时 vy < 0

偏右且较远 -> APPROACH_RIGHT
vx > 0，同时 vy > 0
```

也就是利用麦克纳姆轮的全向能力，一边接近目标，一边横向对位。

## 2. 连续控制公式

水平误差：

```text
ex = (cx - 5000) / 5000
```

经过中心死区后，连续生成横移参考：

```text
vy = max_vy * lateral_gain * ex
```

并做限幅和平滑。

电脑阶段暂时使用目标框面积模拟距离：

```text
area = (w / 10000) * (h / 10000)
```

距离误差：

```text
distance_error = (stop_area_ratio - area) / stop_area_ratio
```

连续生成前进参考：

```text
vx = max_vx * approach_gain * distance_error
```

实际值会限幅到 `0 ~ max_vx`，并经过低通平滑。

> 注意：上车后，`vx` 的距离控制应该改为 ToF 距离闭环；目标框面积只作为辅助信息。

## 3. 状态标签

连续速度是主要控制量，action 只是方便人观察：

```text
SEARCH
HOLD
APPROACH_LEFT
APPROACH
APPROACH_RIGHT
ALIGN_LEFT
ALIGN_RIGHT
STOP
```

其中：

- `APPROACH_LEFT`：向前 + 向左横移
- `APPROACH_RIGHT`：向前 + 向右横移
- `ALIGN_LEFT/RIGHT`：已经较近，不再前进，只横向对位
- `STOP`：近距离且已居中

## 4. 防抖与安全行为

新增：

- 中心死区 `center_deadband`
- 前进/停车面积滞回 `stop_area_ratio` / `resume_area_ratio`
- 速度一阶低通 `smoothing_alpha`
- 目标确认帧数 `target_confirm_frames`
- 目标丢失确认 `lost_confirm_frames`
- 丢失目标后立即清零前进速度，不保留上一帧前进命令

## 5. 协议 v2

模拟 FPGA 现在不仅能看到 action，还能收到连续参考速度：

```text
vx  m/s
vy  m/s
omega rad/s
```

线上实际编码为：

```text
vx_mm_s      int16
vy_mm_s      int16
omega_mrad_s int16
```

这些仍然只是**车体参考速度**，不是 PWM。

实机 FPGA 仍必须执行：

```text
ToF安全限制
急停
心跳超时
速度限幅
麦轮逆运动学
四轮PID
PWM输出
```

## 6. 运行

窗口1：

```powershell
cd E:\gowin\ling_shu_vision
.\.venv\Scripts\python.exe -m scripts.mock_fpga_receiver
```

窗口2：

```powershell
cd E:\gowin\ling_shu_vision
.\.venv\Scripts\python.exe -m src.main --config config\config.yaml
```

推荐直接调用 `.venv\Scripts\python.exe`，这样不需要激活 PowerShell 虚拟环境，也不会遇到执行策略问题。

## 7. 你应该观察什么

人在远处、偏左：

```text
action   : APPROACH_LEFT
vx       : 正数
vy       : 负数
```

从左侧慢慢走到画面中央：

```text
vy 的绝对值应逐渐减小到 0
```

人在中央慢慢远离摄像头：

```text
目标框面积变小
vx 应逐渐增大
```

慢慢靠近摄像头：

```text
vx 应逐渐减小
达到 stop_area_ratio 后 vx 立即变为 0
```

这就是这次升级最重要的验证点。
