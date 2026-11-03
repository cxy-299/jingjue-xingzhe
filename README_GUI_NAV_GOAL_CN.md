# GUI 选终点与 FPGA 目标帧（2026-10-16）

离线审查更新：发送结果与后台状态分开显示，HTTP 拒绝不会被轮询覆盖；2 秒未消费的目标自动丢弃，错误导航配置会锁定下发；最近写入目标单独保留帧序号。这些是本地源码更新，尚未部署到 Pi。完整差距及待实测模板见 [审查报告](output/review/TOPIC3_LOGIC_AUDIT_2026-10-16_CN.md)。

当前阶段：只完成树莓派网页选点、路线预览和有保护的终点帧下发。FPGA 断电时只测试网页，不下发；电机、ToF、IMU 尚未联调，不把 LED 导航预览当作小车自主行驶。

## 页面操作

1. 在 2 m × 2 m、20 × 20 格地图上点击终点，或输入 X/Y 格坐标后按“按格坐标预览”。左下角为 `(0,0)`，X 向右、Y 向上；起点固定 `(18,1)`。
2. 检查终点米坐标、格坐标和蓝色路线。红色实体障碍、安全膨胀区及不可达终点不能发送。
3. FPGA 上电并确认运行预期位流后，才勾选“已确认 FPGA 已上电”，输入现场设置的导航控制口令，再点击“发送终点到 FPGA”并确认。修改终点后必须重新确认供电。
4. 页面“待发送 / 已写入树莓派 USB 串口”只代表 Pi 端处理进度。当前没有 FPGA→Pi 的接收回执、执行进度或到达确认；USB 串口连接状态也不能证明 FPGA 已上电。

SIN7 联调版本由树莓派根据同一 `nav-map-2m.json` 计算四邻域路径，并发送地图 ID `0x2601`、终点格和 `0x21` 完整路径帧；FPGA 仍用编码器逐格闭环执行。树莓派不发送 PWM。发送成功只表示 USB 串口写入，仍需要 FPGA 状态回传或现场观察确认执行结果。

## 安全开关

`config/config-pi.yaml` 的 `navigation.goal_tx_enabled` 默认 `false`，即网页可以预览但不能发目标。后端还要求非空 `navigation.control_token`，且发送时 Pi 的串口已打开。打开 USB 串口不等于 FPGA 有电，因此网页另要求人工确认。

若之后只验收 **NAV3 LED-only 位流**的终点接收，可在确认板上位流、供电及现场安全后，临时把 `goal_tx_enabled` 改为 `true`，并在树莓派本机给 `control_token` 设置一个自选口令，然后只重启树莓派 GUI 服务。验收完改回 `false`。不要把真实口令写进仓库。切换到电机位流前必须单独完成急停、定位和驱动安全验收。

## 部署到树莓派

本地工程改动不会自动出现在 `http://192.168.137.129:8080/`。在 Windows PowerShell 中，确认 Pi SSH 能连接后，逐条复制下列文件；登录密码只在 SSH/SCP 的交互提示中输入，不要发给别人。本步骤不碰 FPGA，也不重启电脑。Pi 上原有 `config-pi.yaml` 不覆盖，以免改掉摄像头或串口配置。

```powershell
scp E:\gowin\ling_shu_vision\web\dashboard.html pi@192.168.137.129:/home/pi/ling_shu_vision/web/
scp E:\gowin\ling_shu_vision\src\web_gui.py pi@192.168.137.129:/home/pi/ling_shu_vision/src/
scp E:\gowin\ling_shu_vision\src\config.py pi@192.168.137.129:/home/pi/ling_shu_vision/src/
scp E:\gowin\ling_shu_vision\src\comm\protocol.py pi@192.168.137.129:/home/pi/ling_shu_vision/src/comm/
scp E:\gowin\ling_shu_vision\scripts\build_nav_map.py pi@192.168.137.129:/home/pi/ling_shu_vision/scripts/
scp E:\gowin\ling_shu_vision\config\nav-map-2m.json pi@192.168.137.129:/home/pi/ling_shu_vision/config/
ssh pi@192.168.137.129 "sudo systemctl restart ling-shu-vision-gui.service"
```

如 Pi IP 已改变，请把命令中的地址换成实际地址。刷新网页（Ctrl+F5），应能看到 X/Y 格坐标输入和“发送终点到 FPGA（锁定）”。可用 Pi 端 `curl http://127.0.0.1:8080/api/nav/map` 检查地图 API；默认禁发状态下 `POST /api/nav/goal` 应返回 HTTP 423。

## 本地验证

```powershell
Set-Location E:\gowin\ling_shu_vision
node tests\test_nav_preview.js
python -m unittest discover -s tests -p test_nav_goal_api.py -v
```

测试仅使用固定地图、浏览器脚本与本机 HTTP，不连接串口，也不需要 FPGA 供电。

## SIN7 树莓派路径帧更新（2026-10-26）

`src/web_gui.py` 已改为调用 `shortest_path_from()` 和 `pack_nav_path()`，解决旧网页只发送 `0x20` 终点帧、SIN7 需要 `0x21` 完整路径帧的协议差异。部署后先保持驱动板 12 V 关闭，在 Pi 上执行：

```bash
cd /home/pi/ling_shu_vision
python3 -m py_compile src/web_gui.py src/comm/protocol.py scripts/build_nav_map.py
python3 -m pytest -q tests/test_nav_goal_api.py tests/test_task14_integration.py
```

当前 Pi 工程的 USB CH340 通道是 115200 传感器/协议通道；SIN7 车控命令实际已由 PC 的 COM9 蓝牙 9600 通道验证。若要让 Pi 独立下发 SIN7 的 F/B/S 或路径帧，必须把 Pi 的串口接到 FPGA 的车控 RX/蓝牙链路并使用对应 9600 波特率，不能把 115200 诊断 TX 当作车控输入。完成硬件桥接前，Pi 网页可以做视觉和路径预览，PC 驾驶台负责实际 SIN7 命令下发。
