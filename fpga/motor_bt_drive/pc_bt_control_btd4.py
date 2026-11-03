"""BTD5 off-ground GUI with explicit Windows COM transport status.

No Bluetooth ACK exists in the FPGA protocol. A successful local write does
not prove reception; use the FPGA LED and COM6 diagnostics to confirm it.
"""

import argparse
from datetime import datetime
import tkinter as tk
from tkinter import ttk

import serial
from serial.tools import list_ports

from pc_bt_control import CommandGate


class TrackedPort:
    def __init__(self, port):
        self.port = port
        self.tx_bytes = 0
        self.last_tx = "无"
        self.rx_buffer = b""

    def write(self, data):
        count = self.port.write(data)
        if count != len(data):
            raise serial.SerialTimeoutException(f"仅写入 {count}/{len(data)} 字节")
        self.tx_bytes += count
        self.last_tx = datetime.now().strftime("%H:%M:%S")
        return count

    def close(self):
        self.port.close()

    def poll_lines(self):
        """Non-blocking receive; returns complete ASCII telemetry lines."""
        data = self.port.read(512)
        if data:
            self.rx_buffer += data
        lines = []
        while b"\n" in self.rx_buffer:
            line, self.rx_buffer = self.rx_buffer.split(b"\n", 1)
            line = line.rstrip(b"\r")
            if line:
                lines.append(line.decode("ascii", "replace"))
        return lines


def main():
    parser = argparse.ArgumentParser(description="BTD5 四轮离地蓝牙遥控与编码器回传")
    parser.add_argument("--port", default="COM9", help="蓝牙 SPP 输出串口")
    args = parser.parse_args()
    root = tk.Tk()
    root.title("FPGA 四轮离地遥控 · BTD5-TX · 编码器回传")
    root.geometry("580x600")
    root.minsize(520, 540)
    port_name = tk.StringVar(value=args.port)
    state = tk.StringVar(value="未连接")
    detail = tk.StringVar(value="驱动板 12 V 保持关闭；先检查蓝牙供电与 Windows 配对")
    counts = tk.StringVar(value="TX 成功 0 字节 · 最近 无 · FPGA ACK 不支持")
    telemetry = tk.StringVar(value="蓝牙回传：尚未收到编码器诊断（需要 BTD5 位流）")
    motion_allowed = tk.BooleanVar(value=False)
    gate = None
    link = None
    timer = None

    def log(message):
        history.configure(state="normal")
        history.insert("end", f"[{datetime.now():%H:%M:%S}] {message}\n")
        history.see("end")
        history.configure(state="disabled")

    def show(label, color, message):
        state.set(label)
        lamp.configure(fg=color)
        detail.set(message)

    def cancel_repeat():
        nonlocal timer
        if timer is not None:
            root.after_cancel(timer)
            timer = None

    def close_link():
        nonlocal gate, link
        cancel_repeat()
        motion_allowed.set(False)
        if gate is not None:
            gate.held = None
        gate = None
        if link is not None:
            try:
                link.close()
            except (serial.SerialException, OSError):
                pass
            link = None

    def fault(context, exc):
        log(f"{context}失败：{type(exc).__name__}: {exc}")
        close_link()
        show("发送故障 · 已断开", "#b00020",
             "蓝牙串口写入不可靠。保持/关闭驱动板 12 V，检查模块供电及 Windows 蓝牙连接后手动重连。")

    def stop():
        cancel_repeat()
        if gate is None:
            return
        try:
            gate.stop()
        except (serial.SerialException, OSError) as exc:
            fault("停止 S", exc)
            return
        log("TX: S 停止（本地写入成功，非 FPGA 回执）")
        detail.set("S 已本地写入；FPGA 另有 300 ms 失联停车。")

    def pulse():
        nonlocal timer
        timer = None
        if gate is None or not gate.held:
            return
        try:
            gate.refresh()
        except (serial.SerialException, OSError) as exc:
            fault("方向刷新", exc)
            return
        timer = root.after(100, pulse)

    def press(direction):
        nonlocal timer
        if gate is None:
            detail.set("先连接串口；打开 COM 口不等于蓝牙链路可靠。")
            return
        if not motion_allowed.get():
            detail.set("先确认四轮离地，再勾选“允许离地试转”。")
            return
        try:
            accepted = gate.press(direction)
        except (serial.SerialException, OSError) as exc:
            fault("发送方向", exc)
            return
        if not accepted:
            log("换向先发送 S；松开后重新按目标方向")
            return
        log(f"TX: {direction} 按住；每 100 ms 刷新")
        if timer is None:
            timer = root.after(100, pulse)

    def refresh_ports():
        found = [p.device for p in list_ports.comports()]
        choices = sorted(set(found + [port_name.get()]))
        ports.configure(values=choices)
        log("发现串口：" + (", ".join(found) if found else "无"))

    def connect():
        nonlocal gate, link
        if link is not None:
            return
        name = port_name.get().strip().upper()
        if not name:
            detail.set("请选择 COM 口")
            return
        show("正在连接", "#9a6700", f"打开 {name}，发送 S + 标准档 3")
        try:
            raw = serial.Serial(name, 9600, bytesize=serial.EIGHTBITS,
                                parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
                                timeout=0, write_timeout=0.5)
            link = TrackedPort(raw)
            gate = CommandGate(link)
            gate.set_speed("3")
        except (serial.SerialException, OSError) as exc:
            fault("连接或初始化", exc)
            return
        show(f"{name} 已打开 · TX 正常", "#087443",
             "S + 3 已本地写入；协议无 FPGA ACK，须以 LED/COM6 诊断确认接收。")
        log(f"{name} 9600/8N1 已打开；TX: S3 完成")

    def disconnect():
        if link is None:
            return
        stop()
        close_link()
        show("已手动断开", "#555555", "重新连接前确认电机 12 V 关闭。")
        log("手动断开；试转许可已清除")

    def speed(preset):
        if gate is None:
            detail.set("请先连接蓝牙串口")
            return
        cancel_repeat()
        try:
            gate.set_speed(preset)
        except (serial.SerialException, OSError) as exc:
            fault("调速", exc)
            return
        target = {"1": 12, "2": 16, "3": 20}[preset]
        log(f"TX: S{preset}；目标 {target} 计数/10 ms")
        detail.set("已停车并本地写入档位；重新按方向键生效。")

    def update_counts():
        if link is None:
            counts.set("TX 成功 0 字节 · 最近 无 · FPGA ACK 不支持")
        else:
            counts.set(f"TX 成功 {link.tx_bytes} 字节 · 最近 {link.last_tx} · FPGA ACK 不支持")
        root.after(200, update_counts)

    def poll_telemetry():
        if link is not None:
            try:
                for line in link.poll_lines():
                    if line.startswith("M"):
                        telemetry.set("蓝牙回传：" + line)
                    log("RX: " + line)
            except (serial.SerialException, OSError) as exc:
                fault("读取编码器诊断", exc)
        root.after(50, poll_telemetry)

    def on_close():
        if gate is not None:
            stop()
        close_link()
        root.destroy()

    tk.Label(root, text="仅限四轮离地试验；不是落地/比赛控制", fg="#b00020").pack(pady=(9, 4))
    top = tk.Frame(root)
    top.pack(pady=4)
    tk.Label(top, text="串口").pack(side="left", padx=4)
    ports = ttk.Combobox(top, textvariable=port_name, width=13)
    ports.pack(side="left", padx=4)
    tk.Button(top, text="刷新", command=refresh_ports).pack(side="left", padx=3)
    tk.Button(top, text="连接", command=connect).pack(side="left", padx=3)
    tk.Button(top, text="断开", command=disconnect).pack(side="left", padx=3)
    lamp = tk.Label(root, textvariable=state, fg="#555555", font=("Microsoft YaHei UI", 11, "bold"))
    lamp.pack(pady=(8, 1))
    tk.Label(root, textvariable=detail, wraplength=530, justify="center").pack(pady=(0, 6))
    tk.Label(root, textvariable=counts, fg="#444444").pack()
    tk.Label(root, textvariable=telemetry, fg="#075985", wraplength=530).pack(pady=(2, 4))
    tk.Checkbutton(root, text="允许离地试转（取消勾选立即发 S）",
                   variable=motion_allowed,
                   command=lambda: stop() if not motion_allowed.get() else None).pack(pady=8)
    pad = tk.Frame(root)
    pad.pack(pady=3)
    for label, command, row, col in (
        ("前 F", "F", 0, 1), ("左 L", "L", 1, 0),
        ("后 B", "B", 1, 1), ("右 R", "R", 1, 2),
    ):
        button = tk.Button(pad, text=label, width=10, height=2)
        button.grid(row=row, column=col, padx=3, pady=3)
        button.bind("<ButtonPress-1>", lambda event, d=command: press(d))
    root.bind_all("<ButtonRelease-1>", lambda event: stop() if gate and gate.held else None)
    tk.Button(root, text="停止 S", command=stop, bg="#ffdddd", width=14).pack(pady=5)
    tk.Label(root, text="闭环档位；调速先停车。连续运行最多 3 秒；S0 后须先发 S。").pack()
    speeds = tk.Frame(root)
    speeds.pack(pady=5)
    for label, preset in (("慢 12", "1"), ("中 16", "2"), ("标准 20", "3")):
        tk.Button(speeds, text=label, width=10,
                  command=lambda value=preset: speed(value)).pack(side="left", padx=4)
    tk.Label(root, text="串口事件（本地写入日志，不代表 FPGA 已收到）：").pack(anchor="w", padx=12)
    history = tk.Text(root, height=8, state="disabled", wrap="word")
    history.pack(fill="both", expand=True, padx=12, pady=(2, 9))

    def check_focus():
        if gate and gate.held and root.focus_displayof() is None:
            stop()

    root.bind_all("<FocusOut>", lambda event: root.after(20, check_focus))
    root.protocol("WM_DELETE_WINDOW", on_close)
    refresh_ports()
    update_counts()
    poll_telemetry()
    root.mainloop()


if __name__ == "__main__":
    main()
