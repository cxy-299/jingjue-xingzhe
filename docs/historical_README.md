# 灵枢智行——树莓派视觉识别程序框架

该工程用于**先在电脑上完成视觉链路开发**，后续迁移到 Raspberry Pi 4B + Camera Module 3。

## 总体数据链

`Camera/视频 → OpenCV采集 → YOLO检测 → 目标筛选 → 结构化坐标 → UART → ACG720`

视觉端只负责“看到了什么、在哪里”，**不直接输出PWM**。ACG720继续负责麦轮运动学、编码器闭环、PID、ToF安全、急停和AI超时保护。

## 电脑端现在可以完成

- USB/笔记本摄像头或视频文件测试
- YOLO模型加载与推理
- 目标框显示、主目标筛选
- 输出 class / confidence / cx / cy / w / h
- UART协议打包与CRC16
- 串口发送与心跳
- CSV日志
- 数据集图片采集
- 协议单元测试

## Windows安装

建议 Python 3.10/3.11：

```bat
python -m venv .venv
.venv\Scripts\activate
python -m pip install -U pip
pip install -r requirements-pc.txt
```

## 第一次运行

默认用电脑摄像头，串口关闭：

```bat
python -m src.main --config config/config.yaml
```

按 `q` 退出。

## 模型

默认 `yolo11n.pt`，有网络时 Ultralytics 可自动获取通用预训练模型。后续训练自己的阀门、仪表、灭火器等类别后，把模型放入：

```text
models/best.pt
```

并改配置：

```yaml
model:
  path: models/best.pt
```

## 树莓派迁移

树莓派到货后主要修改：

```yaml
camera:
  backend: picamera2
```

Camera Module 3 由 Picamera2 采集，其余检测、目标筛选、UART协议和主循环保持一致。

树莓派建议：

```bash
sudo apt install -y python3-picamera2 python3-opencv
python3 -m venv --system-site-packages .venv
source .venv/bin/activate
pip install -r requirements-pi.txt
```

## UART协议

帧格式：

```text
AA 55 | VERSION | TYPE | SEQ(2) | LEN(2) | PAYLOAD | CRC16(2)
```

目标帧 `TYPE=0x10`，Payload：

```text
timestamp_ms  uint32
valid         uint8
class_id      uint16
confidence    uint16   # 0~10000
cx            uint16   # 0~10000
cy            uint16
w             uint16
h             uint16
```

心跳帧 `TYPE=0x01`，Payload：`uptime_ms uint32`。

坐标统一归一化到0~10000。例如 `cx=5000` 表示目标中心位于图像水平中心，FPGA无需关心摄像头实际分辨率。

## 推荐开发顺序

1. `python scripts/test_camera.py`
2. `python scripts/test_detector.py`
3. `python -m src.main`
4. `pytest -q`
5. 开启串口，与ACG720联调
6. 用 `scripts/capture_dataset.py` 采图
7. 训练自定义 `best.pt`
8. 树莓派切换 Picamera2
9. 再考虑导出 NCNN 等ARM部署格式


## PC模拟决策阶段

当前版本新增视觉决策模拟器，串口仍保持关闭。主程序会把视觉观测转换成：

- SEARCH：未检测到目标，模拟原地搜索
- ALIGN_LEFT：目标偏左，模拟麦轮左横移
- ALIGN_RIGHT：目标偏右，模拟麦轮右横移
- APPROACH：目标已居中且视觉面积较小，模拟向前接近
- STOP：目标已居中且视觉面积达到阈值，模拟停车
- HOLD：状态尚未连续稳定达到设定帧数，暂不改变动作

运行：

```bash
python -m src.main --config config/config.yaml
```

配置参数在 `config/config.yaml` 的 `decision` 段。`stop_area_ratio` 仅用于电脑端视觉距离模拟，正式机器人停车应以 ToF / 安全传感器为准。

# 当前第一阶段：树莓派识别、ACG720 串口与电脑 GUI

请先按 [板载验收清单](BOARD_UART_GUI_ACCEPTANCE_CN.md) 操作；该阶段不连接电机、
ToF 或 IMU。电脑 GUI 由树莓派 `src.web_gui` 提供，访问树莓派实际 IP 的 `:8080`。
网页上的串口计数仅证明树莓派本地写入，FPGA 接收以实体 LED 验收。后续导航
的 2×2 米地图草案位于 `config/map-2m-stage1.yaml`，目前不参与运行。

