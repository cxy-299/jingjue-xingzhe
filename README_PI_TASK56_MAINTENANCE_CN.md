# 树莓派任务五/六视觉 GUI 人工维护手册

适用版本：2026-10-26 任务五/六 GUI。适用硬件：Raspberry Pi 4B、IMX708 CSI 摄像头、树莓派视觉服务。

## 1. 正确打开网页

健康检查地址只用于确认服务存活：

```text
http://树莓派IP:8080/health
```

实际操作界面必须打开根地址：

```text
http://树莓派IP:8080/
```

不要使用电脑的 `http://127.0.0.1:8080/`；`127.0.0.1` 指向当前打开浏览器的电脑。树莓派 IP 可在 Pi 终端执行：

```bash
hostname -I
```

例如树莓派地址为 `192.168.137.129` 时，浏览器应打开 `http://192.168.137.129:8080/`，然后按 Ctrl+F5。

## 2. 启动和检查服务

```bash
sudo systemctl restart ling-shu-vision-gui.service
sleep 8
systemctl is-active ling-shu-vision-gui.service
curl -sS -i --max-time 5 http://127.0.0.1:8080/health
```

预期服务为 `active`，健康检查返回 `HTTP/1.0 200 OK` 和 `ok`。查看日志：

```bash
sudo journalctl -u ling-shu-vision-gui.service -n 60 --no-pager
```

## 3. 相机检查

树莓派新系统使用：

```bash
rpicam-hello --list-cameras
```

预期出现类似：

```text
0 : imx708 [4608x2592 10-bit]
```

若显示 `No cameras available!`：关闭树莓派电源，重新插紧 CSI 排线，两端锁扣完全压下，确认摄像头接在树莓派 CSI 插座而不是 FPGA 的 OV5640 插座，再上电检测。日志中的 `Camera unavailable: list index out of range` 表示服务运行但没有可用摄像头。

## 4. 更新任务五/六 GUI

Windows PowerShell 上传：

```powershell
scp E:\gowin\ling_shu_vision\output\board\pi-task56-gui-2026-10-26.tar pi@树莓派IP:/home/pi/
```

Pi 端备份、解包和检查：

```bash
cd /home/pi/ling_shu_vision
tar -czf /home/pi/pi-task56-before.tgz src/web_gui.py src/comm/protocol.py scripts/build_nav_map.py web/dashboard.html
tar -xf /home/pi/pi-task56-gui-2026-10-26.tar -C /home/pi/ling_shu_vision
python3 -m py_compile src/web_gui.py src/comm/protocol.py scripts/build_nav_map.py
sudo systemctl restart ling-shu-vision-gui.service
```

回滚：

```bash
sudo systemctl stop ling-shu-vision-gui.service
tar -xf /home/pi/pi-task56-before.tgz -C /home/pi/ling_shu_vision
sudo systemctl start ling-shu-vision-gui.service
```

## 5. 任务五：视觉目标识别

打开树莓派根网页，在“目标类别”输入 `bottle` 或 `person`，点击“观察”，确认视频出现识别框、置信度、中心坐标和识别数量。也可以直接点击“识别物品”表格中的一行，自动把该类别填入目标类别框。绿色框表示当前控制目标，橙色框表示其他识别物品。红瓶二次筛选在 `config/config-pi.yaml` 的 `red_bottle` 小节配置，修改后重启服务。

## 6. 任务六：目标搜索和跟随状态

- “搜索目标”：锁定输入类别，持续等待识别结果。
- “锁定并跟随”：锁定输入类别并持续上报确认视觉帧。
- “观察”：解除类别锁定，恢复普通识别。

页面状态含义：`已锁定 · bottle` 表示类别已锁定；`目标已找到：已上报确认帧` 表示当前帧发现目标；`搜索中：未发现锁定类别` 表示当前帧没有目标；`跟随目标已确认：持续上报视觉帧；当前 FPGA 未接入视觉执行器` 表示树莓派已完成视觉状态判断，但电机仍由 PC ToF 驾驶台执行。

当前网页完成识别、类别锁定、搜索状态和视觉帧上报。指定对象的实际电机跟随需要 FPGA 增加视觉执行帧接口，或由 PC 驾驶台接收视觉结果后发送 F/B/L/R/S；页面显示“已锁定”不代表车辆已经移动。

## 7. 树莓派与 FPGA 串口边界

树莓派当前 USB CH340 通道通常是 115200 传感器/诊断通道，SIN7 车控蓝牙链路是 COM9、9600。树莓派网页可以完成视觉识别和状态上报；实际 SIN7 电机控制继续使用 PC 驾驶台，除非另接树莓派到 FPGA 车控 RX 并匹配 9600 波特率。

## 8. 常见故障

| 现象 | 处理 |
|---|---|
| 浏览器显示 127.0.0.1 拒绝连接 | 改用 `http://树莓派IP:8080/` |
| `/health` 返回 ok，根网页无视频 | 检查 `rpicam-hello --list-cameras` 和服务日志 |
| `No cameras available!` | 断电重插 CSI 排线，确认摄像头接树莓派 |
| 页面仍显示旧地图 | Ctrl+F5；确认 Pi 已解包最新 `dashboard.html` |
| 任务按钮无状态变化 | 查看 `/api/status`，确认服务已重启且网页来自树莓派 IP |
| 视觉帧已上报但车辆不动 | 当前 SIN7 尚未接收视觉执行帧；使用 PC SIN7 ToF 驾驶台或增加 FPGA 视觉接口 |

## 9. 维护记录

每次修改记录日期、Pi IP、服务状态、相机型号、模型 SHA-256、目标类别、置信度、任务模式、网页截图和 `journalctl` 首个错误。涉及电机时另记录 FPGA 版本码、ToF 距离、IMU 状态、四路编码器和 12V 状态。

## 10. 2026-10-26 视觉验收记录

IMX708 画面和 YOLO `bottle` 识别正常。目标在画面内时显示“目标已找到/确认帧已上报”；移出画面后显示搜索中或目标丢失；目标重新出现后再次识别；点击“锁定并跟随”后任务状态持续更新。该记录证明任务五的目标识别、任务六的目标搜索和视觉状态机通过。当前树莓派仍只上报视觉帧，SIN7 尚未接入视觉执行帧，因此没有把这次记录写成车辆已经完成电机跟随。
