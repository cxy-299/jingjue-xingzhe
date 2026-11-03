# 实现与接口

## 文件

`miniprogram/` 是零 npm 依赖的原生 WXML/WXSS/JS 工程。`lib/demo.js` 提供内置离线演示，`lib/client.js` 提供电脑网关请求队列、会话、序号、过期时间和生命周期撤销。`pages/index/` 使用单页四标签，切标签不会销毁执行中的导航状态；手动按压期间切换标签会先停止。

`gateway/core.py` 实现单会话控制与400ms租约；`server.py` 是标准库 HTTP + 有期限的主线程消息队列；`pc_adapter.py` 将白名单动作送回原 Tk 控制器，并通过固定树莓派地址转发视觉请求。`start_pc_gateway.py` 是唯一启用网关的电脑入口，普通 `pc_unified_console.py` 启动方式保持没有网关。

生产控制器只增加可选工厂、快照/白名单适配和本地停止通知。没有更改 RTL、位流、ToF/PID参数、固件租约、原始状态机和传感器解析。差异保存在 `docs/desktop-integration.patch`。这是独立扩展包，之前提交的赛事 RAR 不自动包含本次小程序代码。

## HTTP v1

除健康检查外，所有请求都要求头 `Authorization: Bearer <本次配对码>`。最大 JSON 请求8192字节，不接受任意URL、任意命令或原始串口帧。

- `GET /v1/health`：协议版本与演示标识，不含控制许可。
- `POST /v1/session`：JSON `{"label":"微信驾驶台"}`；使旧会话失效、停车并返回 session_id/server_time_ms/lease_ms。
- `GET /v1/state`：原驾驶台快照和 remote 许可状态。请求成功不代表运动已执行。
- `POST /v1/action`：session_id、seq、deadline_ms、action、payload。客户端使用服务器时钟偏移。命令有效窗口最大800ms，当前客户端发送500ms；本地排队超过400ms不再发送。
- `GET /v1/vision/frame`：固定 Pi `/snapshot.jpg` 的 JPEG 快照，无独立串口操作。

动作包括 `arm`、`heartbeat`、`stop`、`manual.move/release/speed`、`nav.preview/pose/start`、`vision.search/lock/prepare`、`task.read/start`、`follow.start/digit`、`turn.start`、`avoid.enable/disable` 和 `pid.set`。

`vision.lock` 必须携带当前识别列表的 detection_id 与对应数字。固定 Pi 后端会再次验证该 ID 是否仍可见及新鲜，网关不猜目标。Pi任务准备/目标确认是异步请求，排队接收不宣称 Pi/FPGA 已确认。

浏览器布局预览不实现真实 HTTP 传输。小程序真实控制以原驾驶台板端回传为准，动作响应中的 accepted 仅表示网关接收并调用白名单入口。

## 参考

微信官方维护的 [小程序 API TypeScript 定义](https://github.com/wechat-miniprogram/api-typings)及[应用生命周期定义](https://github.com/wechat-miniprogram/api-typings/blob/master/types/wx/lib.wx.app.d.ts)。开发者工具、网络域名和真机预览应以当前[微信小程序官方文档](https://developers.weixin.qq.com/miniprogram/dev/framework/ability/network.html)和实际 AppID 配置为准。
