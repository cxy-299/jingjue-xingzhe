"""Windows Bluetooth SPP dead-man control for the *off-ground* BTD4 test.

Requires: pip install pyserial. No FPGA S1 press is required by BTD4.
No motor command is sent on connection. Keep the driver 12 V off until the
off-ground hardware checks have been completed.
"""

import argparse
import tkinter as tk
from tkinter import messagebox

import serial


class CommandGate:
    """Only a held direction may be refreshed. Every release emits STOP."""

    def __init__(self, port):
        self.port = port
        self.held = None

    def press(self, direction):
        if direction not in "FBLR":
            raise ValueError("invalid direction")
        if self.held and self.held != direction:
            self.stop()
            return False  # require a new key press after STOP
        if self.held is None:
            self.held = direction
            self.port.write(direction.encode("ascii"))
        return True

    def refresh(self):
        if self.held:
            self.port.write(self.held.encode("ascii"))

    def stop(self):
        self.held = None
        self.port.write(b"S")

    def set_speed(self, preset):
        if preset not in "123":
            raise ValueError("invalid speed preset")
        self.stop()
        self.port.write(preset.encode("ascii"))


def main():
    parser = argparse.ArgumentParser(description="BTD4 离地蓝牙遥控")
    parser.add_argument("--port", default="COM9", help="蓝牙 SPP 输出串口")
    args = parser.parse_args()

    root = tk.Tk()
    root.title("FPGA 四轮离地遥控 · BTD4")
    root.geometry("420x390")
    status = tk.StringVar(value="未连接；驱动板 12 V 保持关闭")
    motion_allowed = tk.BooleanVar(value=False)
    gate = None
    link = None
    timer = None

    def stop():
        nonlocal timer
        if timer is not None:
            root.after_cancel(timer)
            timer = None
        if gate is not None:
            try:
                gate.stop()
            except serial.SerialException as exc:
                status.set(f"停止指令发送失败：{exc}；请关闭驱动板 12 V")
                return
        status.set("已发送 S；FPGA 还设有 300 ms 失联停车")

    def pulse():
        nonlocal timer
        timer = None
        if gate is not None and gate.held:
            try:
                gate.refresh()
            except serial.SerialException as exc:
                gate.held = None
                status.set(f"串口异常：{exc}；请关闭驱动板 12 V")
                return
            timer = root.after(100, pulse)

    def press(direction):
        nonlocal timer
        if gate is None:
            status.set("请先连接蓝牙串口")
            return
        if not motion_allowed.get():
            status.set("先确认四轮离地，再勾选“允许离地试转”")
            return
        try:
            accepted = gate.press(direction)
        except serial.SerialException as exc:
            status.set(f"串口异常：{exc}；请关闭驱动板 12 V")
            return
        if not accepted:
            status.set("换向已发送 S；松开后重新按目标方向")
            return
        status.set(f"按住 {direction}：每 100 ms 发送；松开即停")
        if timer is None:
            timer = root.after(100, pulse)

    def connect():
        nonlocal link, gate
        if link is not None:
            return
        try:
            link = serial.Serial(args.port, 9600, timeout=0.2, write_timeout=0.2)
            gate = CommandGate(link)
            gate.set_speed("3")
        except (serial.SerialException, OSError) as exc:
            if link is not None and link.is_open:
                link.close()
            link = None
            gate = None
            messagebox.showerror("连接失败", f"{args.port}: {exc}\n请关闭 XCOM 对此串口的占用。")
            return
        status.set(f"{args.port} 已连接；无需 S1，确认离地后勾选试转")

    def select_speed(preset):
        if gate is None:
            status.set("请先连接蓝牙串口")
            return
        try:
            gate.set_speed(preset)
        except serial.SerialException as exc:
            status.set(f"调速发送失败：{exc}；请关闭驱动板 12 V")
            return
        counts = {"1": 12, "2": 16, "3": 20}[preset]
        status.set(f"已发送 S + 速度档 {preset}（目标 {counts} 计数/10 ms）；重新按方向")

    def on_close():
        stop()
        if link is not None:
            link.close()
        root.destroy()

    tk.Label(root, text="仅限四轮离地试验；非落地/比赛控制", fg="red").pack(pady=8)
    tk.Button(root, text=f"连接 {args.port}", command=connect).pack()
    tk.Checkbutton(root, text="允许离地试转（取消勾选立即发 S）",
                   variable=motion_allowed,
                   command=lambda: stop() if not motion_allowed.get() else None).pack(pady=7)
    pad = tk.Frame(root)
    pad.pack(pady=10)
    for label, command, row, col in (
        ("前 F", "F", 0, 1), ("左 L", "L", 1, 0),
        ("后 B", "B", 1, 1), ("右 R", "R", 1, 2),
    ):
        button = tk.Button(pad, text=label, width=9, height=2)
        button.grid(row=row, column=col, padx=3, pady=3)
        button.bind("<ButtonPress-1>", lambda event, d=command: press(d))
    # Capture release anywhere in this Tk process, including outside the button.
    root.bind_all("<ButtonRelease-1>", lambda event: stop() if gate and gate.held else None)
    tk.Button(root, text="停止 S", command=stop, bg="#ffdddd").pack()
    tk.Label(root, text="闭环速度档位：先停车再选档；方向刷新持续时可连续运行").pack(pady=(8, 0))
    speeds = tk.Frame(root)
    speeds.pack()
    for label, preset in (("慢 12", "1"), ("中 16", "2"), ("标准 20", "3")):
        tk.Button(speeds, text=label, width=10,
                  command=lambda value=preset: select_speed(value)).pack(side="left", padx=4)
    tk.Label(root, textvariable=status, wraplength=370).pack(pady=8)
    def check_focus():
        if gate and gate.held and root.focus_displayof() is None:
            stop()

    root.bind_all("<FocusOut>", lambda event: root.after(20, check_focus))
    root.protocol("WM_DELETE_WINDOW", on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
