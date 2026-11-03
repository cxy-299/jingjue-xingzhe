# 赛题三固定地图导航预览工程

2026-10-16 离线修订：已增加障碍终点提前拒绝、串口半帧超时及全地图自检；九项 ModelSim 结果、比赛任务差距和后续验收模板见 [逻辑审查报告](../../output/review/TOPIC3_LOGIC_AUDIT_2026-10-16_CN.md)。本轮仅修改源码，未重新生成/覆盖下述历史 NAV3 位流，未部署实板；新源码需重新综合/PnR 后才能下板。

地图尺寸为 2 m × 2 m，20 × 20 格，每格 10 cm；坐标原点在左下。起点固定为 `(18,1)`，即车体中心 `(185,15)` cm，初始朝向 `+Y`。实体障碍和安全膨胀区来自 `../../config/nav-map-2m.json`，由 `../../scripts/build_nav_map.py` 生成 `nav_map_20x20.mem`。当前地图为 v4-balanced：保留原版 A–D 位置并各缩短约 2 格。修改障碍后必须重新生成地图文件和 PDF，并更新地图 ID；不能只改 GUI 或只改 FPGA。

## 已实现的边界

- `fixed_grid_bfs.v` 在 FPGA 内用四邻域 BFS 求固定起点到终点的最短格路径，找到后逐个给出路点。
- `acg720_nav_preview.v` 把串口合法终点帧接到规划器，只驱动 LED2–LED7，**不连接电机**；原串口验收工程不变。
- Pi 发送协议帧类型 `0x20`，载荷是地图 ID `0x2601`（小端）和 `x,y` 各 1 字节。FPGA 校验 CRC、版本、地图 ID、坐标范围后才发出一拍终点脉冲。
- GUI 点击只预览；默认不允许发送，须显式启用和确认。现在尚无 FPGA→Pi 的回执，GUI 只表示串口写入成功，不能表示 FPGA 已到达终点。

## ModelSim 手动仿真

在 Transcript 输入：

```tcl
do E:/gowin/ling_shu_vision/fpga/nav/run_modelsim.do
```

期望先出现 `PASS tb_fixed_grid_bfs: 34-step route, 3 other goals, safe waypoints, blocked/start/out-of-range goals`，再出现 `PASS tb_acg720_nav_preview: UART -> CRC/map ID -> FPGA BFS -> LED, no motor outputs`。第一项覆盖示例终点 `(2,17)` 的 34 步、其他三个方位终点、路点不落在障碍内、障碍内目标拒绝、起点即终点、越界拒绝。第二项用真实 UART 时序检查协议到规划的整条链路。`busy` 在搜索时为 1，找到路线后 `ready=1`、`steps=34`。`advance_i` 是同一时钟域的一拍有效脉冲，每个高电平时钟都会消费一个路点；不能当作可长时间保持的确认电平。若没有两行 PASS，不得据此下板。

脚本顺序运行两个顶层，Wave 窗口最后显示第二项集成测试。若要单独看第一项波形，可在 Transcript 中重新执行 `vsim -voptargs=+acc sim_nav.tb_fixed_grid_bfs`、`add wave -r sim:/tb_fixed_grid_bfs/*`、`run -all`，再点击 Wave 工具栏的 Zoom Full。

## LED 预览（SRAM 板载联调）

LED2 运行闪烁；LED3 心跳/视觉链路存活；LED4 曾收到合法地图终点帧；LED5 搜索中；LED6 找到可用路线；LED7 不可达或串口/CRC 错误。此顶层故意没有电机输出端口，避免把尚未经运动安全验证的规划结果直接用于车轮。

2026-10-15 已使用 `gw_sh.exe build_preview.tcl` 完成综合、布局布线和位流生成。工作区当前 NAV3 位流在 50 MHz 约束下最差 setup 余量 4.867 ns、无 setup/hold 违规；I/O 报告仅有时钟、S0、Pi UART RX 和 6 个 LED，没有电机引脚。ModelSim 两项回归均 PASS，包含逐格校对显式地图常量。JTAG 扫描到 `GW5AT-60B`；NAV3 已临时下载 SRAM，测试前后只读 User Code 均为 `0x4E415633`。实板障碍格 `(11,4)` 得到 LED4/7 亮、LED6 灭；随后可达目标 `(2,17)` 得到 LED4/6 亮、LED5/7 灭，符合拒绝障碍、清除错误并重新规划的 LED 级验收预期。尚无路点回传和电机路径跟踪，不能据此称小车已具备自主导航。

本次 Programmer 使用 `SRAM Program and Verify` 时，写入完成、状态码为 `0x70026020`，但读回校验提示 `Verify failed at 0`。该状态码的 `done_final=1`、`security_final=1`、CRC/ID 错误位为 0；Arora V 默认安全位会禁止配置后的 SRAM 读回。因此可凭状态和 LED 判断位流已运行，但不能宣称“读回校验通过”。后续只使用临时 SRAM，不写 Flash。

历史 NAV2 曾把障碍格 `(11,4)` 错判为可达；NAV3 改用显式地图常量后该反例的 LED 验收已通过。详见 `../../output/board/NAV_LED_PREVIEW_BOARD_TEST_2026-10-15.md` 的 NAV3 小节。此结果不包含本轮新源码，更不代表实车绕障已通过。

## 尚未完成

片上存储器并未映射为 BSRAM，而是使用寄存器/逻辑资源；PnR 报告显示约 12% 逻辑、15% 寄存器、0 BSRAM。当前规划假设车辆每次从固定起点出发，尚未接入编码器/IMU 定位、ToF 动态避障、路径跟踪和四轮控制，也没有 FPGA→Pi 路径回传。驱动板和传感器未就绪时，不能宣称已实现实车自主导航。
