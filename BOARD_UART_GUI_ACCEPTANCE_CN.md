# 第一阶段：树莓派识别、FPGA 串口、电脑 GUI 板载验收

本阶段**不接电机驱动、ToF、IMU**。现有 ACG720 验收位流仅驱动板载 LED2–LED7，不输出 PWM。`config/map-2m-stage1.yaml` 只是后续导航坐标草案，不参与本阶段程序运行。

## 当前检查结果（2026-10-14）

- 重新构建当前源码，Gowin 综合与布局布线成功；50 MHz 约束下 setup/hold 违例数均为 0，Fmax 报告为 144.676 MHz。独立目录 `fpga/acg720_uart_bringup/verify_20261014` 中复跑 ModelSim：RTL/testbench 编译均为 0 错误、0 警告，`PASS tb_acg720_uart_bringup: UART, CRC, fields, heartbeat, timeouts, no-target`。
- FTDI 总线与串口驱动均为 `2.12.36.20`；下载器与 FPGA JTAG 链只读扫描成功，目标为 `GW5AT-60B`、ID `0x0001481B`。本次没有重启电脑，也没有擦写 Flash。
- 首次选择 `SRAM Program and Verify` 时，写入完成而读回报 `Verify failed at 0`。生成配置 `impl/pnr/device.cfg` 的 `security_bit_enable = true`；[高云官方配置手册](https://www.gowinsemi.com/upload/database_doc/41/document/5b96299fe6aa7.pdf)说明带安全位的数据不能读回验证。因此改用仅 `SRAM Program`，工具报告完成。用户目视确认 LED2 闪烁；这证明测试顶层正在运行，但不替代串口端到端验收。
- 已恢复树莓派 SSH 登录；树莓派枚举到板载 CH340E USB 串口 `/dev/ttyUSB0`，稳定设备路径为 `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`。仅备份并修改了树莓派上的 `config/config-pi.yaml`：`class_names` 从 `person` 改为 `bottle`，串口从 `/dev/serial0` 改为上述稳定路径；原配置保留为 `config-pi.yaml.before-usb-uart-20261014`。只重启了树莓派视觉 GUI 服务，**没有重启电脑或树莓派**。
- 通过树莓派 `/dev/ttyUSB0`、115200 bps 实发 40 组左右交替的 bottle 视觉帧及心跳帧，程序无写入错误；用户现场观察到 LED3–LED6 在测试期间亮起、LED7 未亮。按本验收顶层的 LED 映射，这支持 FPGA 已接收到有效视觉数据，且未显示 CRC/串口帧错误。测试后用户报告 LED2 仍闪烁、LED6/7 不亮；当前 GUI 场景没有检测到目标，不能从这次观察单独证明红瓶识别能力。
- 树莓派 GUI 服务已恢复为 `active`。电脑访问 `http://192.168.137.129:8080/` 与 `/snapshot.jpg` 均返回 HTTP 200（快照为 JPEG），`/api/status` 报告 `online=true`、约 1.8 FPS、`serial_connected=true`、串口路径正确、持续增加的发送帧数且错误为空。当前 FPGA 仅有单向接收和 LED 状态，没有 FPGA→树莓派确认帧；GUI 的“串口已连接”仅表示树莓派成功打开端口，板端接收的证据来自 LED 观察。
- 已先备份树莓派原测试脚本为 `serial_fpga_test.py.before-stage-test-20261014`，再同步本地带中文阶段注释的新版脚本；树莓派 `py_compile` 通过，文件 SHA-256 与本地一致。首轮三阶段时第二、三阶段持续时间过短，用户未看清，因此不以首轮作为实体灯号判据。
- 随后延长测试：约 20 秒目标帧、20 秒无目标帧、15 秒静默，并在切换到无目标时即时提示。脚本无 UART 写入错误；用户现场确认三阶段 LED 变化**全部符合预期**：有目标时 LED3–LED6 亮；无目标时 LED3/4 保持亮、LED5/6 熄灭；停止发送并超过看门狗时间后 LED3–LED6 短暂全灭；LED7 始终不亮。测试后 GUI 服务为 `active`，状态接口报 `online=true`、`serial_connected=true`、发送计数增长且无串口错误。由此，固定测试帧的树莓派→FPGA 串口、目标有效/失效及超时逻辑通过实机验收。
- 实物瓶子测试：GUI 状态连续出现 `bottle`，串口连接与发送计数正常；用户观察到 LED5/6 随手中瓶子出现而亮、移开后灭。移开并对准无瓶背景后，连续 20 次状态采样均为 `target_class=无`、`alignment_state=SEARCH`。场景曾同时出现多个瓶状检测，因此此项只证明通用 bottle 与 LED 联动，不证明选中的一定是红瓶。
- GUI 图像问题定位：`/api/status` 帧号增长，`/stream.mjpg` 4 秒输出约 440 KB，但嵌入浏览器的视频图像停留在旧帧，图像内状态与实时状态面板不一致。已备份树莓派旧页面为 `web/dashboard.html.before-snapshot-20261014`，将页面改为完成一张 `/snapshot.jpg` 后再请求下一张、URL 带时间戳防缓存，并显示实际图像加载时间。网页 JavaScript 语法检查通过，树莓派返回新版页面；用户在 Ctrl+F5 后确认“画面更新”时间及红瓶画面均持续刷新。仅替换网页文件，未重启服务或设备。

## 后续按顺序验收

1. 下载器与目标器件已识别；后续重新接线仍应在 FPGA 断电状态下核对方向，**不要重启电脑，也不要接电机电源**。
2. 带安全位的当前位流应选 **SRAM Program**，载入 `fpga/acg720_uart_bringup/impl/pnr/acg720_uart_bringup.fs`；不选读回 Verify，不执行 Erase/Flash。已完成一次 SRAM 写入并观察到 LED2 闪烁。断电后 SRAM 配置会丢失。
3. 树莓派 USB-A 接 ACG720 板载 CH340E UART Type-C，速率 `115200 8-N-1`；树莓派和 FPGA 各自供电。树莓派的视觉服务与测试脚本不能同时占用串口。
4. 确定性左右目标与心跳帧、无目标帧、停止发送后的 1.5 秒看门狗及 LED3–LED7 实机观察均已通过；后续修改 UART 协议、RTL 或线缆后需回归这项测试。
5. 电脑 GUI 页面、快照、状态接口、实际动态画面、USB 串口连接与发送统计已通过；真实瓶子的通用 bottle 识别与 LED5/6 联动也已通过。当前尚无真实红色水瓶与非红瓶的区分测试。
6. 上述通信验收完成后，才把 `config/config-pi.yaml` 中 `target.red_bottle.enabled` 改为 `true`，用真实红瓶、蓝瓶、红色背景分别测试并调 `min_red_ratio`。这一步才可称为红色水瓶筛选的实物验证。

树莓派能连通后，阶段 4–5 可按以下顺序运行（在树莓派终端，不是在 Windows PowerShell）：

```bash
cd /home/pi/ling_shu_vision
sudo systemctl stop ling-shu-vision-gui.service
./.venv/bin/python -m scripts.serial_fpga_test --port /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0 --count 10
sudo systemctl start ling-shu-vision-gui.service
```

本地新版包含 `src/detection/red_bottle.py`、`target_selector.py`、`main.py`、
`web_gui.py` 和 `web/dashboard.html`。三阶段测试脚本已同步；树莓派应用主体除两项配置值外仍是旧版，
后续启用红瓶二次筛选前，先备份并同步相应代码；不要直接覆盖实机相机校准值。

现有 UART 是树莓派单向发送；GUI 的发送统计只证明本地串口写入。FPGA 实际接收仍以实体 LED 验收为准。板卡原理图虽显示 CH340E 同时连接 FPGA_UART_RX/TX，本阶段未加入回传协议，因此 GUI 不显示“FPGA 已确认”。当前通过 LED 只验收了固定测试目标帧，不能等同于整套自主导航验收。

## 2×2 米地图约定

原点设在左下角，X 向右、Y 向上。起点车体位于右下角边缘；按约 20 cm 车宽和 5 cm 边距，中心暂放 `(1.85 m, 0.15 m)`。车头方向暂假设朝 +Y，终点尚未确定。随机放置的障碍物不预先写入固定地图；后续导航需由 ToF 实时发现并更新局部障碍。当前没有定位和避障模块，地图文件**不会控制小车移动**。

## 点击地图路线预览（2026-10-14）

- 电脑 GUI 下方增加 2×2 米地图：选择终点模式下点击格子显示路线；切换“标记 / 擦除障碍”后点击格子可模拟随机障碍，也可载入示例或清空。
- 此浏览器预览使用 20×20、10 cm 网格的四邻域广度优先搜索；按 20 cm 车宽 + 5 cm 余量将手动障碍和边界膨胀 15 cm。无路时明确显示“不可达”，不会画出假路线。它与 `config/map-2m-stage1.yaml` 草案中的 5 cm 网格尚未统一，后续实机实现需统一坐标与分辨率。
- `node tests/test_nav_preview.js` 通过最短路、障碍绕行、完全隔断三项检查。树莓派旧网页已备份为 `web/dashboard.html.before-nav-preview-20261014`；仅替换 HTML，无电脑 / 树莓派重启。HTTP 200 且新版地图标识已确认。
- **此页面没有目标下发接口**，所画障碍不是 ToF 数据，所画路线也不是 FPGA 计算结果。比赛所需的 FPGA 导航仍待定位、ToF、规划、路径跟踪与电机闭环接入和单独验收。
