# 树莓派4B部署说明

赛题三 FPGA 串口协同方案见：`README_TOPIC3_FPGA_UART_CN.md`。

本机已完成部署的逐步记录、实时网页 GUI 和日常维护方法见：

```text
README_PI_MAINTENANCE_CN.md
```

目标：先把 PC 已验证的视觉侧部署到 Raspberry Pi 4B + Camera Module 3。

本阶段不需要真实 ToF，也不需要接 ACG720。

## 1. 首次相机检查

```bash
rpicam-hello -t 5000
```

能正常看到 Camera Module 3 画面后再继续。

## 2. 安装环境

在工程根目录：

```bash
chmod +x install_pi.sh run_pi.sh
./install_pi.sh
```

虚拟环境使用：

```text
--system-site-packages
```

这是因为 Picamera2/libcamera 推荐由 Raspberry Pi OS 的 apt 管理。

## 3. 无GUI相机冒烟测试

```bash
./.venv/bin/python -m scripts.pi_camera_smoke_test --config config/config-pi.yaml
```

正常输出：

```text
[OK] Picamera2 frame captured
[OK] shape=(480, 640, 3)
[OK] saved=logs/pi_camera_test.jpg
```

## 4. 跑 YOLO + 左右对位

```bash
./run_pi.sh
```

或者：

```bash
./.venv/bin/python -m src.main --config config/config-pi.yaml
```

终端会持续输出：

```text
[VISION] state=ALIGN_LEFT  valid=True cx=3210 ex=-0.358 vy=-0.080
[VISION] state=CENTERED    valid=True cx=4992 ex=-0.002 vy=+0.000
[VISION] state=ALIGN_RIGHT valid=True cx=7190 ex=+0.438 vy=+0.101
```

没有人时：

```text
[VISION] state=SEARCH valid=False ...
```

## 5. 与电脑“模拟FPGA + Mock ToF”联调

树莓派和电脑接同一个局域网。

Windows 查询电脑 IPv4：

```powershell
ipconfig
```

把 `config/config-pi-to-pc.yaml`：

```yaml
mock_fpga:
  enabled: true
  host: 192.168.1.100
  port: 9999
```

中的 `192.168.1.100` 改成电脑真实 IPv4。

电脑运行：

```powershell
python -m scripts.mock_fpga_receiver
```

树莓派运行：

```bash
./.venv/bin/python -m src.main --config config/config-pi-to-pc.yaml
```

这样形成：

```text
Camera Module 3
      ↓
Raspberry Pi 4B
YOLO + visual alignment
      ↓ Wi-Fi UDP（仅比赛前联调）
Windows 模拟 FPGA
      +
Mock ToF
```

实机 UART 传输层现已完成。当前 USB-A→ACG720 板载 Type-C 接线使用
`config/config-pi.yaml` 的 `auto_usb_ch340` 向 FPGA 发送纯视觉结果，
UDP 仅保留给电脑模拟 FPGA 联调。

## Raspberry Pi 4 性能建议

第一阶段先保持：

```yaml
camera: 640x480 @ 20 fps
model.imgsz: 416
model.path: yolo11n.pt
display.enabled: false
```

先验证正确性，再做 NCNN 优化。
