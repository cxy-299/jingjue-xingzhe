# 灵枢视觉：树莓派 4B YOLO 部署与维护手册

> 历史记录说明：本文 2026-09-23 的 `person` 与 GPIO `/dev/serial0` 示例用于当时实验。当前赛题三仓库配置已切换为 `bottle` 和 `auto_usb_ch340`（USB-A→ACG720 板载 Type-C）；实机尚需同步配置。普通 `bottle` 检测还不能区分红色。最新验收见 `REPORT_PI_FPGA_UART_2026-10-13.md`。

赛题三 FPGA 串口协议、接线和 RTL 接入方法见
`README_TOPIC3_FPGA_UART_CN.md`。

最后验证日期：2026-09-23

本文记录本次真实部署过程，适用于以下环境：

- Raspberry Pi 4 Model B Rev 1.5
- Camera Module 3（IMX708，自动对焦）
- Raspberry Pi OS Lite 64 位 / Debian 12 Bookworm
- Windows 电脑与树莓派网线直连，不经过路由器
- YOLO11n，树莓派 CPU 推理
- 电脑浏览器实时查看标注画面和传输状态

## 1. 当前部署状态

| 项目 | 当前值 |
| --- | --- |
| 树莓派主机名 | `raspberrypi` |
| 树莓派网口地址 | `192.168.137.129`（DHCP 地址，重启后可能改变） |
| 电脑直连网口地址 | `192.168.137.1` |
| SSH 用户 | `pi` |
| 树莓派工程目录 | `/home/pi/ling_shu_vision` |
| Windows 工程目录 | `E:\gowin\ling_shu_vision` |
| 模型文件 | `/home/pi/ling_shu_vision/yolo11n.pt` |
| 模型 SHA256 | `0ebbc80d4a7680d14987a577cd21342b65ecfd94632bd9a8da63ae6417644ee1` |
| 实时 GUI | `http://192.168.137.129:8080` |
| GUI 服务名 | `ling-shu-vision-gui.service` |
| 系统时区 | `Asia/Shanghai` |

初始登录凭据保存在本机 `E:\gowin\tmp\pi_credentials.txt`，不要把该文件提交到代码仓库或发送给无关人员。首次交付后建议登录树莓派执行 `passwd` 修改密码。

## 2. 本次实际完成的步骤

### 2.1 烧录系统

1. 确认目标为 64 GB SD 卡，对应 Windows 的“磁盘 3”。
2. 使用 Raspberry Pi Imager 烧录官方 Raspberry Pi OS Lite 64 位 Bookworm 镜像。
3. 使用的镜像日期为 2026-06-18。
4. 压缩镜像 SHA256：

   ```text
   df4c6fb0b625204a09ce587f35f01b4d6375cb3ee0f05df71a0eca6c7aeb8f8f
   ```

5. 在启动分区启用 SSH，并创建 `pi` 用户。
6. 把 SD 卡插回树莓派后上电，确认红色 PWR 灯常亮、绿色 ACT 灯有正常读卡闪烁。

### 2.2 建立无路由器直连网络

当前网络拓扑：

```text
互联网
  │
Windows 电脑 WLAN
  │ Windows ICS 共享
电脑网口 192.168.137.1
  │ 网线
树莓派网口 192.168.137.129
```

在 Windows 管理员 PowerShell 中启用共享：

```powershell
powershell -ExecutionPolicy Bypass -File E:\gowin\ling_shu_vision\scripts\windows_pi_network_sharing.ps1 -Action Enable
```

不用共享时关闭：

```powershell
powershell -ExecutionPolicy Bypass -File E:\gowin\ling_shu_vision\scripts\windows_pi_network_sharing.ps1 -Action Disable
```

如果电脑的无线网络名称不是 `WLAN`，或有线网卡不是 `Realtek PCIe GbE Family Controller`，使用参数覆盖：

```powershell
powershell -ExecutionPolicy Bypass -File E:\gowin\ling_shu_vision\scripts\windows_pi_network_sharing.ps1 `
  -Action Enable `
  -InternetConnection "你的无线连接名称" `
  -PiDeviceDescription "你的有线网卡设备名称"
```

连接测试：

```powershell
ping raspberrypi.local
ssh pi@raspberrypi.local
```

如果 `.local` 名称解析失败，执行 `arp -a` 查找 `192.168.137.x` 地址，再用 IP 登录：

```powershell
ssh pi@192.168.137.129
```

### 2.3 复制工程和模型

工程部署位置：

```text
/home/pi/ling_shu_vision
```

模型放置位置：

```text
/home/pi/ling_shu_vision/yolo11n.pt
```

核对模型：

```bash
cd /home/pi/ling_shu_vision
sha256sum yolo11n.pt
```

必须得到：

```text
0ebbc80d4a7680d14987a577cd21342b65ecfd94632bd9a8da63ae6417644ee1
```

### 2.4 安装树莓派 CPU 推理环境

在树莓派执行：

```bash
cd /home/pi/ling_shu_vision
chmod +x install_pi.sh run_pi.sh run_pi_gui.sh
./install_pi.sh
```

安装脚本使用 `apt` 管理 Picamera2、OpenCV 和 CPU 版 PyTorch，并使用带 `--system-site-packages` 的虚拟环境。当前固定版本为：

```text
OpenCV       4.6.0
PyTorch      1.13.0a0（CPU）
Ultralytics  8.3.0
```

注意：不要直接在这台树莓派上执行不带限制的 `pip install -U torch ultralytics`。2026 年的最新 ARM64 PyTorch 包会尝试下载 NVIDIA CUDA 组件，而 Raspberry Pi 4 没有 NVIDIA GPU。工程已通过 `requirements-pi.txt` 固定兼容版本，并让 `apt` 提供 CPU 版 PyTorch。

## 3. 验证相机与 YOLO

### 3.1 相机冒烟测试

```bash
cd /home/pi/ling_shu_vision
./.venv/bin/python -m scripts.pi_camera_smoke_test --config config/config-pi.yaml
```

本次验证结果：

```text
[OK] Picamera2 frame captured
[OK] shape=(480, 640, 3)
[OK] saved=logs/pi_camera_test.jpg
```

测试图片也已复制到 Windows：

```text
E:\gowin\ling_shu_vision\logs\pi_camera_test.jpg
```

### 3.2 命令行 YOLO 验证

```bash
cd /home/pi/ling_shu_vision
./run_pi.sh
```

当前相机中没有控制目标 `person` 时，正常输出：

```text
[VISION] state=SEARCH valid=False cx=0 ex=+0.000 vy=+0.000
```

按 `Ctrl+C` 停止。

### 3.3 实物识别结果

通过实时 GUI 接口，本次实际识别到：

```text
mouse     90.6%
mouse     61.4%
keyboard  56.5%
cup       47.5%
```

这说明 Camera Module 3、YOLO11n、OpenCV、PyTorch 和网页数据通路均已工作。

控制逻辑仍只选择 `config/config-pi.yaml` 中的 `person` 作为对位目标；其他物品会显示橙色检测框，但不会产生横移控制目标。绿色框表示被选中的控制目标。

### 3.4 自动化测试

```bash
cd /home/pi/ling_shu_vision
./.venv/bin/python -m pytest -q tests
```

本次结果：

```text
14 passed
```

## 4. 实时 GUI 使用方法

### 4.1 打开界面

电脑与树莓派网线连接、Windows ICS 已启用后，在电脑浏览器打开：

```text
http://192.168.137.129:8080
```

如果树莓派 IP 改变，则使用：

```text
http://raspberrypi.local:8080
```

页面包含：

- Camera Module 3 实时画面；
- 所有 YOLO 检测框、类别和置信度；
- 当前控制目标、对位状态、中心误差和目标框面积；
- 实时 FPS、分辨率、模型名；
- FPGA UART 本地端口状态、波特率和已发送帧数（不代表接收端已经收到）；
- UDP 调试链路状态；
- 检测物品表格。

健康检查和状态接口：

```text
http://192.168.137.129:8080/health
http://192.168.137.129:8080/api/status
http://192.168.137.129:8080/snapshot.jpg
```

### 4.2 GUI 后台服务管理

GUI 已设置为开机自动启动。常用命令：

```bash
# 查看状态
systemctl status ling-shu-vision-gui.service

# 查看实时日志
journalctl -u ling-shu-vision-gui.service -f

# 重启
sudo systemctl restart ling-shu-vision-gui.service

# 停止
sudo systemctl stop ling-shu-vision-gui.service

# 启动
sudo systemctl start ling-shu-vision-gui.service

# 取消开机启动
sudo systemctl disable --now ling-shu-vision-gui.service
```

注意：Camera Module 3 同一时间只能被一个进程占用。GUI 服务运行时，不要直接启动 `./run_pi.sh` 或相机冒烟测试。需要命令行测试时先执行：

```bash
sudo systemctl stop ling-shu-vision-gui.service
```

测试完成后恢复：

```bash
sudo systemctl start ling-shu-vision-gui.service
```

### 4.3 手动运行 GUI

先停止后台服务，然后执行：

```bash
sudo systemctl stop ling-shu-vision-gui.service
cd /home/pi/ling_shu_vision
./run_pi_gui.sh
```

按 `Ctrl+C` 停止，再恢复后台服务。

## 5. 配置维护

主配置文件：

```text
/home/pi/ling_shu_vision/config/config-pi.yaml
```

当前重要参数：

```yaml
camera:
  width: 640
  height: 480
  fps: 20
  awb_mode: fluorescent
  awb_lock_after_s: 3.0
  colour_gains: [2.40, 1.73]

model:
  path: yolo11n.pt
  conf_threshold: 0.45
  iou_threshold: 0.50
  imgsz: 416
  device: cpu

target:
  class_names: ["person"]
```

修改配置后重启服务：

```bash
sudo systemctl restart ling-shu-vision-gui.service
```

如果希望临时把杯子作为控制目标，可改为：

```yaml
target:
  class_names: ["cup"]
```

测试后应改回 `person`，避免比赛控制逻辑错误。

### 5.1 相机色调与白平衡

2026-09-23 在当前实验室灯光下，使用覆盖画面主体的白纸完成了精确校准。
程序同时修正了 Picamera2 `RGB888` 缓冲区被重复转换所造成的红、蓝通道
互换问题。当前固定白平衡值为：

```text
red=2.40, blue=1.73
```

最终白纸区域实测值：

```text
平均 RGB：R=157.46，G=158.15，B=158.91
三个通道最大偏差：0.92%
```

`colour_gains` 的顺序是 `[红色增益, 蓝色增益]`。只要灯具、相机位置和
使用环境不变，应保留该固定值；固定值可以防止物体进入画面时色调漂移。

如果更换灯光或把设备搬到室外，应先删除或注释 `colour_gains`，再按环境
设置 `awb_mode`，让相机重新自动校色：

| 使用环境 | `awb_mode` 建议值 |
| --- | --- |
| 当前实验室荧光灯 | `fluorescent` |
| 普通室内灯、混合光 | `indoor` |
| 室外或窗边自然光 | `daylight` |
| 需要相机持续适应不同光源 | `auto`，同时把 `awb_lock_after_s` 改成 `0` |

没有配置 `colour_gains` 且 `awb_lock_after_s` 大于 0 时，相机会在服务启动
后自动校色 3 秒，再锁定自动测得的数值。需要重新做精确校准时，让无颜色
图案的白纸覆盖画面中央大部分区域，并避免纸面反光或镜头直接对准灯具。

## 6. 与电脑模拟 FPGA 联调

直连网络下，`config/config-pi-to-pc.yaml` 已使用电脑地址：

```yaml
mock_fpga:
  enabled: true
  host: 192.168.137.1
  port: 9999
```

电脑端运行：

```powershell
cd E:\gowin\ling_shu_vision
python -m scripts.mock_fpga_receiver
```

树莓派端先停止 GUI 服务，再使用联调配置：

```bash
sudo systemctl stop ling-shu-vision-gui.service
cd /home/pi/ling_shu_vision
./.venv/bin/python -m src.web_gui \
  --config config/config-pi-to-pc.yaml \
  --host 0.0.0.0 \
  --port 8080
```

此时网页仍可观看，状态栏会显示 UDP 目标 `192.168.137.1:9999`。

## 7. 更新代码或模型

更新前先停止服务：

```bash
sudo systemctl stop ling-shu-vision-gui.service
```

从 Windows 复制单个文件示例：

```powershell
scp E:\gowin\ling_shu_vision\config\config-pi.yaml pi@raspberrypi.local:/home/pi/ling_shu_vision/config/
```

替换模型示例：

```powershell
scp E:\path\to\new_model.pt pi@raspberrypi.local:/home/pi/ling_shu_vision/
```

然后在 `config/config-pi.yaml` 中更新 `model.path`，执行一次相机/YOLO 测试，最后恢复服务：

```bash
sudo systemctl start ling-shu-vision-gui.service
```

## 8. 日常健康检查

```bash
# 温度
vcgencmd measure_temp

# 欠压和降频标志
vcgencmd get_throttled

# 磁盘空间
df -h /

# 服务状态
systemctl is-active ling-shu-vision-gui.service

# 最近 50 行日志
journalctl -u ling-shu-vision-gui.service -n 50 --no-pager

# FPGA 硬件串口应指向 ttyAMA0
ls -l /dev/serial0
```

本次部署完成时：

```text
空闲温度：37.0°C
GUI + YOLO 持续运行温度：60.3°C
最终供电/降频状态：throttled=0x0
磁盘：59G，总使用 4.2G，可用约 51G
服务：active / enabled
```

## 9. 供电问题（重要）

部署过程中曾读到：

```text
throttled=0x50005
```

这表示当时存在欠压并发生降频。之后读数变为：

```text
throttled=0x50000
```

这表示当时的欠压已经消失，但系统仍显示“曾发生欠压/降频”的历史记录。最终在 GUI 与 YOLO 持续运行、温度约 60.3°C 时再次检查，读数已经为 `throttled=0x0`。仍应保留下面的供电维护要求，避免负载或外设增加后再次欠压。

维护要求：

- 使用稳定的 5V/3A USB-C 电源；
- 优先使用树莓派官方电源或质量可靠的短粗电源线；
- 不要从电脑普通 USB 口给树莓派供电；
- YOLO 满载运行时再次执行 `vcgencmd get_throttled`；
- 正常、无历史故障的理想值为 `throttled=0x0`。

欠压会导致推理变慢、相机异常、随机重启，严重时会损坏 SD 卡文件系统。

## 10. 常见故障排查

### 网口灯亮但无法 SSH

1. 确认 Windows ICS 仍然启用；
2. 检查电脑有线网卡是否为 `192.168.137.1`；
3. 执行 `ping raspberrypi.local`；
4. 执行 `arp -a` 查找新的 `192.168.137.x` 地址；
5. 确认树莓派红色 PWR 灯稳定、绿色 ACT 灯有活动。

### GUI 页面打不开

```bash
systemctl status ling-shu-vision-gui.service
journalctl -u ling-shu-vision-gui.service -n 80 --no-pager
ss -lntp | grep 8080
```

电脑测试：

```powershell
Test-NetConnection 192.168.137.129 -Port 8080
```

### 提示相机正在使用

说明另一个进程占用了 Camera Module 3：

```bash
sudo systemctl restart ling-shu-vision-gui.service
```

不要同时运行 GUI、`run_pi.sh` 和相机测试脚本。

### 有画面但没有识别框

- 检查镜头保护膜是否已撕掉；
- 物品距离建议约 0.5–2 米；
- 保证光线充足，避免逆光；
- 等待 Camera Module 3 自动对焦；
- 可把 `conf_threshold` 从 `0.45` 临时降到 `0.30` 做排查；
- YOLO11n 默认 COCO 模型只能识别其训练类别，不是所有自定义物品都能识别。

### 画面偏蓝、偏黄或颜色来回变化

1. 当前实验室环境应确认 `colour_gains` 仍为 `[2.40, 1.73]`；
2. 如果已经更换光源，删除固定增益，再检查 `awb_mode` 是否符合现场光源；
3. 修改配置后执行 `sudo systemctl restart ling-shu-vision-gui.service`；
4. 等待约 10 秒刷新网页，再观察白色物体是否呈中性白；
5. 在日志中确认已启用手动白平衡，或者已完成自动白平衡锁定。

查看最近一次锁定值：

```bash
journalctl -u ling-shu-vision-gui.service -n 50 --no-pager | grep -E "Manual white balance|White balance locked"
```

### 绿色 ACT 灯异常固定节奏闪烁

固定次数循环闪烁通常表示启动文件或 SD 卡错误。先断电，重新插拔 SD 卡；仍失败时重新烧录已验证的官方 Bookworm 64 位镜像。排障时记录每一轮闪烁次数，不要只描述“闪了几下”。

## 11. 安全关机与备份

不要直接拔电。正常关机：

```bash
sudo poweroff
```

等待绿色 ACT 灯停止活动后再断电。

建议在重大修改前备份：

```powershell
scp -r pi@raspberrypi.local:/home/pi/ling_shu_vision E:\gowin\backup\
```

至少备份配置文件、自训练模型和日志；`.venv` 不必备份，可通过 `./install_pi.sh` 重建。
