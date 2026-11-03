"""SIN12 console: one fixed firmware profile, explicit mutually exclusive modes.

Bluetooth carries motors, sensors and FPGA task state; USB belongs to the Pi.
The firmware profile describes the expected image; it never programs the FPGA.
Legacy profiles remain explicit command-line options for maintenance only.
"""

from __future__ import annotations

import json
import queue
import threading
import urllib.request
import argparse
import math
import struct
import sys
import time
from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import ttk

import serial
from serial.tools import list_ports

from pc_runtime_policy import (continue_local_forward, can_acknowledge_block,
                               map_navigation_reply, manual_avoid_status_text,
                               confirmed_digit_follow_trigger, navigation_obstacle_point)
from pc_bt_control import CommandGate
from pc_bt_control_btd4 import TrackedPort
from pc_async_transport import AsyncTrackedPort
from pc_follow_sequence import FollowCommandSequencer
from pc_unified_model import (
    btd6_nav_supported,
    load_preview_map,
    nav_send_supported,
    pack_btd6_route,
    parse_sensor_status,
    parse_vision_status,
    parse_turn_status,
    parse_motor_fault_snapshot,
    route_codes,
    preview_goal,
    route_directions,
)
from scripts.build_nav_map import add_dynamic_obstacle, shortest_path_from, FPGA_NEIGHBOR_ORDER
from src.core.follow_control import FollowController
from src.comm.protocol import pack_turn_relative, pack_mission_request
from src.comm.pid_tuning import pack_pid_config, parse_pid_status, parse_wheel_sample, parse_control_status, mission_lease_ms
from src.comm.mission import parse_mission_status
from src.comm.mission_readiness import check_mission_readiness
from src.core.a4_targets import target_label
from src.comm.autonav import MAP_ID as AUTONAV_MAP_ID, pack_autonav_goal, parse_autonav_status, counts_per_cell_for_version


GRID = 20
CELL = 22
CANVAS_SIZE = GRID * CELL


class ScrollPanel(tk.Frame):
    """Scroll only this panel; status and telemetry stay outside its viewport."""
    def __init__(self, master, **kwargs):
        super().__init__(master, **kwargs)
        self.canvas = tk.Canvas(self, highlightthickness=0, width=1)
        bar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=bar.set)
        bar.pack(side="right", fill="y")
        self.canvas.pack(side="left", fill="both", expand=True)
        self.inner = tk.Frame(self.canvas)
        self.item = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.inner.bind("<Configure>", self._content_changed)
        self.canvas.bind("<Configure>", self._viewport_changed)
        self.bind_all("<MouseWheel>", self._wheel, add="+")

    def _content_changed(self, event=None):
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _viewport_changed(self, event):
        self.canvas.itemconfigure(self.item, width=event.width)
        def wrap(widget):
            for child in widget.winfo_children():
                if isinstance(child, tk.Label) and int(str(child.cget("wraplength"))):
                    child.configure(wraplength=max(200, event.width-30))
                wrap(child)
        wrap(self.inner)

    def _wheel(self, event):
        widget = self.winfo_containing(event.x_root, event.y_root)
        while widget is not None and widget is not self:
            widget = widget.master
        if widget is self and self.inner.winfo_height() > self.canvas.winfo_height():
            self.canvas.yview_scroll(-int(event.delta/120), "units")
            return "break"


def main() -> None:
    parser = argparse.ArgumentParser(description="SIN12 固定版本 · 运动/传感器/导航/视觉任务统一驾驶台")
    parser.add_argument("--port", default="COM9", help="Windows 蓝牙 SPP 输出串口")
    parser.add_argument("--connect", action="store_true", help="启动后连接蓝牙，仅初始化停止与速度档，不授权运动")
    parser.add_argument("--firmware", choices=("SIN9", "SIN10", "SIN11", "SIN12"), default="SIN12",
                        help="默认固定SIN12；旧配置仅供显式回退，此选项不会下载固件")
    parser.add_argument("--log-dir", type=Path, default=Path(__file__).resolve().parents[2] / 'output' / 'board' / 'logs', help="自动保存本次串口收发记录的目录")
    args = parser.parse_args()
    if args.firmware == 'SIN12':
        from scripts.build_nav_map import occupied_cells
        spec = json.loads((Path(__file__).resolve().parents[2]/'config/nav-map-sin12.json').read_text(encoding='utf-8'))
        occupied = occupied_cells(spec)
    else:
        spec, occupied = load_preview_map()
    fixed = set()
    for obstacle in spec["obstacles"]:
        ox, oy = obstacle["min_cell"]
        width, height = obstacle["size_cells"]
        for y in range(oy, oy + height):
            for x in range(ox, ox + width):
                fixed.add(y * GRID + x)

    root = tk.Tk()
    root.title(f"灵枢统一驾驶台 · {args.firmware} · 后台串口与任务状态")
    root.geometry(f"{min(1200, root.winfo_screenwidth()-80)}x{min(900, root.winfo_screenheight()-100)}")
    root.minsize(1040, 650)
    port_name = tk.StringVar(value=args.port)
    sensor_port_name = tk.StringVar(value="COM6")
    link_status = tk.StringVar(value="蓝牙未连接")
    detail = tk.StringVar(value=f"固定{args.firmware}配置；只切控制模式，无需换固件。连接不会授权运动。")
    tx_status = tk.StringVar(value="TX 0 字节 · 无 FPGA 命令回执")
    bluetooth_rx_count = 0
    bluetooth_rx_at = "无"
    preview_status = tk.StringVar(value="点击地图选终点；蓝线仅是电脑预览")
    selected_goal = tk.StringVar(value="未选择")
    motion_allowed = tk.BooleanVar(value=False)
    firmware_confirmed = tk.BooleanVar(value=False)
    nav_allowed = tk.BooleanVar(value=False)
    firmware_name = tk.StringVar(value=args.firmware)
    nav_status = tk.StringVar(value="导航未下发")
    sensor_status = tk.StringVar(value="传感器串口未连接")
    tof_display = tk.StringVar(value="ToF：未连接")
    imu_display = tk.StringVar(value="IMU：未连接")
    fault_display = tk.StringVar(value="FPGA 告警：未收到状态")
    motor_fault_evidence = tk.StringVar(value="电机故障快照：暂无触发记录")
    fault_snapshots = {}
    session_log = args.log_dir / f'console_{datetime.now():%Y%m%d_%H%M%S_%f}.log'
    try:
        session_log.parent.mkdir(parents=True, exist_ok=True)
        session_log.touch(exist_ok=False)
    except OSError:
        session_log = None
    log_location = tk.StringVar(value=f"日志：{session_log}" if session_log else "日志无法写入：请检查目录权限/磁盘空间")
    pid_p=tk.StringVar(value='4');pid_i=tk.StringVar(value='1');pid_d=tk.StringVar(value='0')
    pid_status=tk.StringVar(value='等待R4板端PID回传；旧固件不支持在线调参')
    sync_status=tk.StringVar(value='等待四轮同拍C回传（10ms采样，串口抽样显示）')
    pid_received=0.0;sync_received=0.0;sync_runtime={}
    pid_version=0;control_received=0.0;control_runtime={}
    manual_avoid_status=tk.StringVar(value='普通前进自动绕行：等待R5板端能力/状态回传')
    manual_control_feedback=tk.StringVar(value='操作提示：停车并核对下方条件后，点击启用前进避障')
    manual_control_version=tk.StringVar(value='板端固件：等待K版本回传')
    local_geometry_confirmed=tk.BooleanVar(value=False)
    control_pending=None
    block_ack_attempted=False
    block_episode_at=0.0
    fault_evidence_at={}
    pid_pending=None;pid_deadline=0.0
    pid_sequence=int(time.monotonic()*1000)&0xffff
    control_mode = tk.StringVar(value="manual")
    button_mode = tk.StringVar(value="hold")
    vision_status = tk.StringVar(value="树莓派指定目标：未收到 FPGA 锁定回传")
    vision_runtime = {}
    vision_received_at = 0.0
    vision_lease_timer = None
    vision_enabled_ui = False
    follow_status = tk.StringVar(value="真实跟随未启动：锁定前向 ToF 目标，目标距离 200 mm")
    wheel_lines = {index: tk.StringVar(value=f"M{index}：无回传") for index in range(1, 5)}
    goal: tuple[int, int] | None = None
    route: list[tuple[int, int]] = []
    link: TrackedPort | None = None
    sensor_link: TrackedPort | None = None
    sensor_via_link = False
    gate: CommandGate | None = None
    repeat_timer: str | None = None
    nav_sequence = 0
    dynamic_cells: set[int] = set()
    measured_cells: set[int] = set()
    measured_generations: set[tuple[int,int]] = set()
    map_observation_status=tk.StringVar(value='黄格=本次停稳ToF投影；橙格=人工标记。位置取决于起点、车头、500计数/格及探头偏移。')
    current_cell = tuple(spec["start_cell"])
    pose_confirmed = False
    pose_status = tk.StringVar(value="当前位置未确认：首次运行请确认起点；停车后须重新确认")
    switch_after: str | None = None
    obstacle_latched = False
    pi_fault_latched_ui = False
    last_fault_bits = 0
    last_wheel_fault_mask = 0
    last_sensor_time = 0.0
    sensor_nav_clear = False
    follow_controller = FollowController(
        target_mm=200, distance_deadband_mm=25, hard_stop_mm=100,
        max_forward=0.12, max_reverse=0.06, require_imu=True,
    )
    follow_active = False
    follow_timer: str | None = None
    follow_origin_digit = None
    digit_handoff = None
    digit_handoff_timer = None
    follow_dispatch = FollowCommandSequencer(root.after, root.after_cancel, lambda: gate,
                                            on_error=lambda error: fault('跟随换向', error))
    last_imu_valid = False
    last_tof_valid = False
    last_distance_mm = 0
    last_yaw_deg: float | None = None
    turn_status = tk.StringVar(value="FPGA定点旋转：尚无Z状态回传")
    turn_result = tk.StringVar(value="单击左转90°或右转90°执行一次；到角自动停车，停止S可随时取消")
    yaw_ccw_positive = tk.BooleanVar(value=True)
    turn_timer = None
    turn_enabled = False
    turn_sequence = int(time.monotonic()*1000)&0xffff
    turn_started_at = 0.0
    turn_received_at = 0.0
    turn_runtime = {}

    mission_status=tk.StringVar(value='尚无FPGA任务状态（需实际J帧）')
    mission_result=tk.StringVar(value='先在Pi网页准备语义任务，再读取并启动')
    mission_url=tk.StringVar(value='http://192.168.137.129:8080')
    mission_search_allowed=tk.BooleanVar(value=False)
    mission_job={}
    mission_runtime={}
    mission_received_at=0.0
    mission_started_at=0.0
    mission_last_lease_at=0.0
    mission_link_note=tk.StringVar(value='许可每100ms刷新；FPGA仍按300ms失联停车')
    mission_guidance=tk.StringVar(value='到达距离优先停止平移；居中且距离稳定才报告完成')
    mission_enabled=False
    mission_timer=None
    mission_sequence=0
    mission_reads=queue.Queue()
    mission_read_generation=0

    auto_status=tk.StringVar(value='尚无FPGA N回传；固定配置不能代替板端能力确认')
    auto_result=tk.StringVar(value=f'地图0x{AUTONAV_MAP_ID:04X}；终=已发送终点，估=推算位置；局部绕行点不是地图终点')
    auto_setback=tk.StringVar(value='')
    auto_geometry=tk.BooleanVar(value=False)
    auto_runtime={}
    auto_request_context={}
    auto_map_runtime={}
    auto_received=0.0
    auto_started=0.0
    auto_enabled=False
    auto_sequence=int(time.monotonic()*1000)&0xffff
    auto_timer=None
    auto_last_lease=0.0

    def cancel_auto_loop():
        nonlocal auto_enabled,auto_timer,auto_last_lease
        auto_enabled=False;auto_last_lease=0.0
        if auto_timer is not None:
            root.after_cancel(auto_timer);auto_timer=None

    def auto_lease():
        nonlocal auto_timer,auto_last_lease
        auto_timer=None
        if not auto_enabled:return
        now=time.monotonic()
        matching=(auto_runtime.get('sequence')==auto_sequence and auto_received>=auto_started)
        if (link is None or control_mode.get()!='autonav' or not motion_allowed.get()
            or not nav_allowed.get() or not firmware_confirmed.get() or not auto_geometry.get()
            or not sensor_nav_clear or now-last_sensor_time>1.6
            or (auto_last_lease and now-auto_last_lease>.25)
            or (matching and now-auto_received>1.6)
            or (not matching and now-auto_started>2.5)):
            stop();auto_result.set('导航许可撤销：链路/状态/授权失效；不自动恢复');return
        try:link.write(b'N')
        except (serial.SerialException,OSError) as exc:fault('板内导航续期',exc);return
        auto_last_lease=time.monotonic();auto_timer=root.after(100,auto_lease)

    def start_auto():
        nonlocal auto_enabled,auto_timer,auto_sequence,auto_started,pose_confirmed
        if auto_enabled or auto_runtime.get('active'):
            auto_result.set('导航执行中，终点已锁定；更换终点请先停止并重新确认位置');return
        now=time.monotonic()
        if (args.firmware!='SIN12' or firmware_name.get()!='SIN12' or spec['map_id']!=AUTONAV_MAP_ID
            or control_mode.get()!='autonav' or link is None or not pose_confirmed or goal is None
            or not firmware_confirmed.get() or not nav_allowed.get() or not motion_allowed.get()
            or not sensor_nav_clear or now-last_sensor_time>1.6
            or not auto_received or now-auto_received>1.6):
            auto_result.set('需用--firmware SIN12启动、新鲜N帧、已确认当前位置、终点与全部授权');return
        try:
            if not pid_received or now-pid_received>2.0:
                raise ValueError("需新鲜K版本帧确认板内每格计数；请等待遥测")
            cell_counts=counts_per_cell_for_version(pid_version)
            next_seq=(auto_sequence+1)&0xffff
            packet=pack_autonav_goal(next_seq,current_cell,goal,cell_counts,int(auto_setback.get()),
                auto_geometry.get(),not yaw_ccw_positive.get(),12)
        except (ValueError,TypeError) as exc:auto_result.set(str(exc));return
        stop();auto_sequence=next_seq;auto_enabled=True
        auto_request_context.clear()
        auto_request_context.update(sequence=next_seq,start=tuple(current_cell),goal=tuple(goal),version=pid_version)
        auto_map_runtime.clear()
        dynamic_cells.clear();measured_cells.clear();measured_generations.clear();draw_map()
        def send():
            nonlocal auto_started,pose_confirmed
            if (not auto_enabled or link is None or control_mode.get()!='autonav'
                or not firmware_confirmed.get() or not motion_allowed.get() or not nav_allowed.get()
                or not auto_geometry.get() or not sensor_nav_clear):
                stop();return
            try:link.write(packet)
            except (serial.SerialException,OSError) as exc:fault('发送板内导航终点',exc);return
            auto_started=time.monotonic();pose_confirmed=False
            pose_status.set('位置由FPGA编码器推算；中止后重启须核对车头沿地图+Y及当前位置')
            auto_result.set(f"已发送终点{auto_request_context['goal']} #{auto_sequence}；等待板端同序号、同终点回执")
            log(f'AUTONAV GOAL seq={auto_sequence} bytes={packet.hex(" ")}')
            auto_lease()
        auto_timer=root.after(240,send)

    def cancel_mission_loop():
        nonlocal mission_enabled,mission_timer,mission_last_lease_at,mission_read_generation
        # S/mode/disconnect invalidates in-flight HTTP launch checks too.
        mission_read_generation+=1
        mission_enabled=False
        mission_last_lease_at=0.0
        if mission_timer is not None:
            root.after_cancel(mission_timer);mission_timer=None

    def cancel_turn_loop() -> None:
        nonlocal turn_timer,turn_enabled
        if turn_enabled:
            turn_result.set("定点旋转已停止/取消；不会自动重启")
        turn_enabled=False
        if turn_timer is not None:
            root.after_cancel(turn_timer)
            turn_timer=None

    def log(message: str) -> None:
        nonlocal session_log
        entry = f"[{datetime.now():%Y-%m-%d %H:%M:%S.%f}] {message}\n"
        if session_log is not None:
            try:
                with session_log.open('a', encoding='utf-8') as stream:
                    stream.write(entry)
            except OSError as error:
                log_location.set(f"日志写入失败：{error}")
                session_log = None
        history.configure(state="normal")
        history.insert("end", entry)
        if int(history.index('end-1c').split('.')[0]) > 1500:
            history.delete('1.0', '501.0')
        history.see("end")
        history.configure(state="disabled")

    def draw_map() -> None:
        canvas.delete("all")
        for y in range(GRID):
            for x in range(GRID):
                key = y * GRID + x
                color = ("#ffda55" if key in measured_cells else "#f5a623" if key in dynamic_cells else
                         "#e36e5b" if key in fixed else
                         "#50444a" if occupied[key] else "#17324a")
                px, py = x * CELL, (GRID - 1 - y) * CELL
                canvas.create_rectangle(px, py, px + CELL, py + CELL,
                                        fill=color, outline="#29445b")
                if key in measured_cells:
                    canvas.create_text(px+CELL/2,py+CELL/2,text='测',fill='#17324a',font=('Microsoft YaHei UI',8))
        if route:
            points = []
            for x, y in route:
                points.extend(((x + 0.5) * CELL, (GRID - y - 0.5) * CELL))
            if len(points) >= 4:
                canvas.create_line(*points, fill="#43b4ff", width=4, joinstyle="round")
        for cell, color, label in ((tuple(spec["start_cell"]), "#4ad49b", "起"),
                                   (current_cell if pose_confirmed else None, "#a6f0de", "位"),
                                   ((auto_map_runtime['x'], auto_map_runtime['y']) if args.firmware == 'SIN12'
                                    and auto_map_runtime and not auto_runtime.get('local_mode')
                                    and auto_map_runtime['state'] != 0 and 0 <= auto_map_runtime['x'] < GRID
                                    and 0 <= auto_map_runtime['y'] < GRID else None, "#d59cff", "估"),
                                   (goal, "#ffbd63", "选" if auto_request_context and goal!=auto_request_context['goal'] else "终"),
                                   (auto_request_context.get('goal') if auto_request_context and goal!=auto_request_context['goal'] else None,
                                    "#ffbd63", "终")):
            if cell is None:
                continue
            x, y = cell
            px, py = (x + 0.5) * CELL, (GRID - y - 0.5) * CELL
            canvas.create_oval(px - 10, py - 10, px + 10, py + 10, fill=color, outline="")
            canvas.create_text(px, py, text=label, fill="#06121e", font=("Microsoft YaHei UI", 9, "bold"))

    def choose_goal(x: int, y: int) -> None:
        nonlocal goal, route
        if auto_enabled:
            preview_status.set('执行中的已发送终点已锁定；先停止，确认当前位置后再选新终点');return
        if not (0 <= x < GRID and 0 <= y < GRID):
            goal = None
            route = []
            preview_status.set("终点必须是 0～19 的整数格坐标")
            update_nav_button_state()
            return
        goal = (x, y)
        cells = [1 if i in dynamic_cells or i in measured_cells else bit for i, bit in enumerate(occupied)]
        order = FPGA_NEIGHBOR_ORDER if args.firmware=='SIN12' else ((1,0),(-1,0),(0,1),(0,-1))
        route = shortest_path_from(spec, cells, current_cell, goal, neighbor_order=order)
        selected_goal.set(f"({x}, {y}) · ({(x + 0.5) * 0.1:.2f}, {(y + 0.5) * 0.1:.2f}) m")
        gx.set(str(x))
        gy.set(str(y))
        if len(route) > 1:
            preview_status.set(f"从 {current_cell} 规划：{len(route) - 1} 步 / {(len(route) - 1) * 0.1:.2f} m；{'已确认位置' if pose_confirmed else '位置未确认，禁止下发'}")
        elif route:
            preview_status.set("当前位置已是终点：无需发送零步路径")
        else:
            preview_status.set("终点不可达或位于障碍/安全区；未发送 FPGA")
        draw_map()
        # 选点可能发生在连接和授权之后；此时必须立即重新计算发送按钮状态。
        # 之前遗漏这一刷新，导致路径已生成但按钮仍保持 disabled。
        update_nav_button_state()

    def map_click(event: tk.Event) -> None:
        x = max(0, min(19, int(event.x // CELL)))
        y = max(0, min(19, 19 - int(event.y // CELL)))
        choose_goal(x, y)

    def input_goal() -> None:
        nonlocal goal, route
        try:
            x, y = int(gx.get()), int(gy.get())
        except ValueError:
            goal = None
            route = []
            preview_status.set("请输入整数格坐标 X/Y")
            update_nav_button_state()
            return
        choose_goal(x, y)

    def confirm_position() -> None:
        nonlocal current_cell, pose_confirmed
        pose_confirmed = False
        update_nav_button_state()
        if link is not None:
            stop_navigation()
        try:
            x, y = int(cx.get()), int(cy.get())
        except ValueError:
            pose_status.set("请输入整数格坐标")
            return
        index = y * GRID + x
        if not (0 <= x < GRID and 0 <= y < GRID) or occupied[index] or index in dynamic_cells or index in measured_cells:
            pose_status.set("当前位置越界或位于障碍/安全区，未确认")
            return
        current_cell = (x, y)
        auto_request_context.clear();auto_map_runtime.clear();measured_cells.clear();measured_generations.clear()
        pose_confirmed = True
        pose_status.set(f"人工确认当前位置 {current_cell}；已重新计算路线")
        if goal is not None:
            choose_goal(*goal)
        else:
            draw_map()
            update_nav_button_state()

    def mark_obstacle() -> None:
        nonlocal pose_confirmed
        pose_confirmed = False
        update_nav_button_state()
        if link is not None:
            stop_navigation()
        try:
            x, y = int(ox.get()), int(oy.get())
        except ValueError:
            pose_status.set("请输入整数障碍格坐标")
            return
        if not (0 <= x < GRID and 0 <= y < GRID):
            pose_status.set("障碍格坐标应在 0～19")
            return
        if (x, y) == current_cell:
            pose_status.set("不能把确认的当前位置标记为障碍")
            return
        expanded = add_dynamic_obstacle([0] * (GRID * GRID), GRID, (x, y), radius_cells=1)
        if expanded[current_cell[1] * GRID + current_cell[0]]:
            pose_status.set("障碍安全区覆盖当前位置；先停车并重新确认格坐标")
            return
        dynamic_cells.update(i for i, bit in enumerate(expanded) if bit)
        pose_confirmed = False
        pose_status.set(f"已人工标记障碍 ({x},{y}) 及相邻安全格；需要确认当前位姿后才能下发新路径")
        if goal is not None:
            choose_goal(*goal)
        else:
            draw_map()

    def clear_obstacles() -> None:
        nonlocal pose_confirmed
        if link is not None:
            stop_navigation()
        dynamic_cells.clear()
        measured_cells.clear();measured_generations.clear()
        pose_confirmed = False
        update_nav_button_state()
        pose_status.set("已清除人工临时障碍；请重新确认当前位置")
        if goal is not None:
            choose_goal(*goal)
        else:
            draw_map()

    def cancel_repeat() -> None:
        nonlocal repeat_timer, switch_after
        if repeat_timer is not None:
            root.after_cancel(repeat_timer)
            repeat_timer = None
        if switch_after is not None:
            root.after_cancel(switch_after)
            switch_after = None

    def cancel_vision_loop() -> None:
        nonlocal vision_lease_timer, vision_enabled_ui
        vision_enabled_ui = False
        if vision_lease_timer is not None:
            root.after_cancel(vision_lease_timer)
            vision_lease_timer = None

    def cancel_follow_loop() -> None:
        nonlocal follow_active, follow_timer, follow_origin_digit, digit_handoff, digit_handoff_timer
        follow_active = False
        follow_origin_digit = None
        digit_handoff = None
        if digit_handoff_timer is not None:
            root.after_cancel(digit_handoff_timer)
            digit_handoff_timer = None
        follow_dispatch.cancel()
        if follow_timer is not None:
            root.after_cancel(follow_timer)
            follow_timer = None
        follow_controller.unlock()

    def close_link() -> None:
        nonlocal link, gate, sensor_link, sensor_via_link
        nonlocal pid_received,sync_received,pid_pending,sync_runtime,pid_version,control_received,control_runtime,control_pending
        pid_received=0.0;sync_received=0.0;pid_pending=None;sync_runtime={}
        auto_request_context.clear();auto_map_runtime.clear();measured_cells.clear();measured_generations.clear()
        pid_version=0;control_received=0.0;control_runtime={};control_pending=None
        manual_avoid_status.set('蓝牙断开；普通前进避障及受阻状态未确认')
        manual_control_feedback.set('操作提示：蓝牙已断开；重新连接后需重新核对并启用')
        manual_control_version.set('板端固件：未连接，旧版本回传已失效')
        pid_status.set('蓝牙断开；PID实际值未确认')
        sync_status.set('蓝牙断开；同步样本已失效')
        cancel_auto_loop()
        cancel_mission_loop()
        cancel_turn_loop()
        cancel_repeat()
        cancel_follow_loop()
        cancel_vision_loop()
        motion_allowed.set(False)
        firmware_confirmed.set(False)
        if gate is not None:
            gate.held = None
        gate = None
        if link is not None:
            try:
                link.close()
            except (serial.SerialException, OSError):
                pass
        link = None
        if sensor_link is not None:
            try:
                sensor_link.close()
            except (serial.SerialException, OSError):
                pass
        sensor_link = None
        sensor_via_link = False
        map_observation_status.set('连接已断开：板端估计位置与本次ToF测点已清除，重连后重新确认起点/航向')
        draw_map()
        update_nav_button_state()

    def fault(context: str, exc: Exception) -> None:
        log(f"{context}失败：{type(exc).__name__}: {exc}")
        close_link()
        link_status.set("蓝牙发送故障 · 已断开")
        detail.set("不能确认停车指令已送达！立即关闭驱动板 12 V，检查蓝牙后再连接。")

    def stop() -> None:
        stopped_direction = gate.held if gate else None
        if control_mode.get()=="turn":control_mode.set("manual")
        cancel_auto_loop()
        cancel_mission_loop()
        cancel_turn_loop()
        cancel_vision_loop()
        cancel_follow_loop()
        cancel_repeat()
        if gate is None:
            return
        try:
            gate.stop()
        except (serial.SerialException, OSError) as exc:
            fault("发送 S 停止", exc)
            return
        caller = sys._getframe(1)
        log(f"UI STOP source={caller.f_code.co_name}:{caller.f_lineno} "
            f"held={stopped_direction} mode={control_mode.get()} style={button_mode.get()}")
        detail.set("S 已本地写入；蓝牙链路没有 FPGA ACK，硬件另有约 300 ms 看门狗。")

    def refresh_motion() -> None:
        nonlocal repeat_timer
        repeat_timer = None
        if gate is None or not gate.held:
            return
        try:
            gate.refresh()
        except (serial.SerialException, OSError) as exc:
            fault("方向刷新", exc)
            return
        repeat_timer = root.after(100, refresh_motion)

    def press(direction: str, source: str = 'unspecified') -> None:
        nonlocal repeat_timer, switch_after, pose_confirmed
        if last_fault_bits & 0x10:
            detail.set("FPGA 已锁存电机 PI 故障：停止试转，检查 12 V 与编码器，排除原因后短按 S0 复位。")
            return
        if gate is None or not firmware_confirmed.get() or not motion_allowed.get():
            detail.set("需连接 COM、核对当前固件并确认四轮离地；导航和手动试转均需单独授权。")
            return
        if control_mode.get() != "manual":
            detail.set("当前为自动导航/安全停车模式，先切换到手动模式。")
            return
        if button_mode.get() == "click" and gate.held == direction:
            stop()
            return
        try:
            accepted = gate.press(direction)
        except (serial.SerialException, OSError) as exc:
            fault("方向发送", exc)
            return
        log(f"UI DIRECTION source={source} direction={direction} "
            f"accepted={accepted} mode={control_mode.get()} style={button_mode.get()}")
        pose_confirmed = False
        pose_status.set("手动行驶后位置未知；导航前须人工确认当前格")
        update_nav_button_state()
        if not accepted:
            # FPGA requires a neutral interval before a direction change.
            # Complete the switch automatically so a quick second click is
            # not lost by the old two-step interaction.
            pending = direction
            gate.held = None
            detail.set(f"换向：已发送 S，等待中性间隔后切换到 {pending}")
            switch_after = root.after(140, lambda d=pending: start_direction(d))
            return
        if repeat_timer is None:
            repeat_timer = root.after(100, refresh_motion)

    def start_direction(direction: str) -> None:
        nonlocal repeat_timer, switch_after
        switch_after = None
        if gate is None or control_mode.get() != "manual" or not motion_allowed.get():
            return
        try:
            gate.press(direction)
        except (serial.SerialException, OSError) as exc:
            fault("换向发送", exc)
            return
        detail.set(f"{direction} 已生效；{'点击再次停止，期间每 100 ms 续期' if button_mode.get() == 'click' else '松开按键停止'}")
        if repeat_timer is None:
            repeat_timer = root.after(100, refresh_motion)

    def mode_changed() -> None:
        if control_mode.get() == 'autonav':
            stop();nav_status.set('SIN12：FPGA规划/扫描/更新障碍，旧版发送路径按钮不可用')
        elif control_mode.get() == 'mission':
            stop()
            nav_status.set('智能任务：Pi筛选语义，FPGA主动扫描、接近与到达停车')
        elif control_mode.get() == "turn":
            stop()
            nav_status.set("定点旋转：输入相对角度，由FPGA以IMU航向闭环执行")
        elif control_mode.get() == "safe":
            stop()
            nav_status.set("安全停车模式：不发送运动指令")
        elif control_mode.get() == "manual":
            stop()
            nav_status.set("手动模式：方向键控制")
        elif control_mode.get() == "vision":
            stop()
            nav_status.set("任务5：数字只触发一次，随后ToF保持20cm；不再按图像左右对准")
        elif control_mode.get() == "follow":
            stop()
            nav_status.set("真实前向跟随：锁定 ToF 目标，目标距离 200 mm")
        else:
            stop()
            nav_status.set("自动导航模式：请选择终点并发送路径")
        update_nav_button_state()

    def follow_send(direction: str) -> None:
        """Send one real follow command, with a neutral gap on reversal."""
        if not follow_active or gate is None:
            return
        try:
            follow_dispatch.send(direction)
        except (serial.SerialException, OSError) as exc:
            fault("跟随指令", exc)

    def follow_tick() -> None:
        nonlocal follow_timer
        follow_timer = None
        if not follow_active:
            return
        if follow_origin_digit is not None and (
                control_mode.get()!='follow' or not control_received or
                time.monotonic()-control_received>2.0 or control_runtime.get('avoid_enabled') or
                auto_runtime.get('active') or mission_runtime.get('active') or turn_runtime.get('active')):
            stop()
            follow_status.set('数字触发ToF跟随已取消：板端模式/避障状态失效；需重新明确启动')
            return
        live = (sensor_link is not None or sensor_via_link) and time.monotonic() - last_sensor_time < 1.6
        if (gate is None or not firmware_confirmed.get() or not motion_allowed.get()
                or not live or not sensor_nav_clear or not last_tof_valid or not last_imu_valid
                or (last_fault_bits & 0x10)):
            if follow_origin_digit is not None:
                stop()
                follow_status.set('数字触发ToF跟随已取消：传感器/许可/链路失效，不自动恢复')
                return
            follow_send("S")
            follow_status.set("真实跟随已停车：ToF/IMU/链路或编码器状态无效")
        else:
            result = follow_controller.update(
                target_valid=True, center_error=0.0,
                distance_mm=last_distance_mm, tof_valid=True,
                imu_valid=True, yaw_deg=last_yaw_deg)
            if result.vx > 0.003:
                direction = "F"
                state = "跟随前进"
            elif result.vx < -0.003:
                direction = "B"
                state = "跟随后退"
            else:
                direction = "S"
                state = "保持 200 mm"
            follow_send(direction)
            follow_status.set(
                (f"数字{follow_origin_digit['digit']}已触发→ToF跟随：" if follow_origin_digit else "真实跟随：")+
                f"{state} · ToF {last_distance_mm} mm · "
                f"误差 {result.distance_error_mm:+d} mm"
            )
        follow_timer = root.after(150, follow_tick)

    def start_real_follow(*, digit_trigger=None) -> bool:
        nonlocal follow_active, follow_timer, follow_origin_digit, pose_confirmed
        if control_mode.get() != "follow":
            control_mode.set("follow")
            mode_changed()
        if (gate is None or not firmware_confirmed.get() or not motion_allowed.get()
                or (sensor_link is None and not sensor_via_link)
                or not last_tof_valid or not last_imu_valid or not sensor_nav_clear
                or time.monotonic()-last_sensor_time>1.6):
            follow_status.set("跟随未启动：先连接蓝牙、核对当前固定固件与运动许可，确认ToF/IMU有效")
            return False
        cancel_follow_loop()
        try:
            gate.set_speed("1")
        except (serial.SerialException, OSError) as exc:
            fault("跟随设置慢速", exc)
            return False
        follow_controller.lock(last_yaw_deg)
        follow_origin_digit = digit_trigger
        pose_confirmed = False
        follow_active = True
        follow_status.set("真实距离跟随已启动：目标200mm；此模式跟随ToF射线，不选择视觉身份")
        nav_status.set("ToF距离跟随执行中：只前进/后退/停止，保持20cm；不再持续核验数字身份，停止S取消")
        follow_timer = root.after(0, follow_tick)
        return True

    def start_visual_execution() -> None:
        nonlocal digit_handoff, digit_handoff_timer
        now=time.monotonic()
        trigger=confirmed_digit_follow_trigger(vision_runtime,vision_received_at,now)
        stop()
        if (firmware_name.get() not in ("SIN9", "SIN10", "SIN11", "SIN12") or link is None or not firmware_confirmed.get()
                or not motion_allowed.get() or control_mode.get() != "vision"):
            detail.set("需指定目标跟随模式、连接、固件核对与运动许可；数字确认后才交接ToF")
            return
        if trigger is None or not sensor_nav_clear or now-last_sensor_time>1.6:
            detail.set("未交接：需FPGA新鲜确认的完整数字及有效IMU/ToF；先在Pi选定数字")
            return
        if pid_version<5 or now-pid_received>2.0 or not control_received or now-control_received>2.0:
            detail.set('未交接：需新鲜K/O回传确认普通前进绕行可关闭，防止ToF跟随触发转向')
            return
        if control_pending is not None:
            detail.set('未交接：请等待当前板端控制确认完成');return
        pending=dict(trigger=trigger,link=link,started=now,ack=(control_runtime['sequence']+1)&255)
        digit_handoff=pending
        try:
            link.write(b'a') # Stopped-only handoff: disable ordinary-F detours.
        except (serial.SerialException,OSError) as exc:
            fault('任务5关闭普通前进绕行',exc);return
        detail.set(f"数字{trigger['digit']}已确认；停车等待ToF交接，关闭普通前进绕行并核对板端回传")
        def handoff():
            nonlocal digit_handoff_timer
            digit_handoff_timer=None
            if digit_handoff is not pending:return
            current=time.monotonic()
            if (link is not pending['link'] or control_mode.get()!='vision' or
                not firmware_confirmed.get() or not motion_allowed.get() or
                current-last_sensor_time>1.6 or not sensor_nav_clear or
                not last_tof_valid or not last_imu_valid or last_fault_bits!=0):
                stop();detail.set('任务5交接取消：许可/传感器/连接状态改变，不自动恢复');return
            if current-pending['started']>3.0:
                stop();detail.set('任务5交接超时：未确认避障关闭/四轮停稳；未启动跟随');return
            acknowledged=(control_received>=pending['started'] and current-control_received<=2.0 and
                          control_runtime.get('sequence')==pending['ack'] and
                          not control_runtime.get('avoid_enabled') and control_runtime.get('recovery_result')==1)
            still=(sync_received>=pending['started'] and current-sync_received<=1.0 and
                   sync_runtime.get('command')==0 and len(sync_runtime.get('speeds',()))==4 and
                   all(abs(v)<=1 for v in sync_runtime['speeds']))
            if (acknowledged and still and current-pending['started']>=.30 and
                not auto_runtime.get('active') and not mission_runtime.get('active') and not turn_runtime.get('active')):
                if start_real_follow(digit_trigger=pending['trigger']):
                    detail.set(f"任务5数字{pending['trigger']['digit']}已触发ToF真实跟随；不再根据图像左右摇摆/丢失停机，S取消")
                    log(f"TASK5 DIGIT_TO_TOF digit={pending['trigger']['digit']} lock={pending['trigger']['lock_id']} target_mm=200; no visual lease")
                return
            digit_handoff_timer=root.after(50,handoff)
        digit_handoff_timer=root.after(300,handoff)

    def turn_lease() -> None:
        nonlocal turn_timer
        turn_timer=None
        if not turn_enabled:
            return
        now=time.monotonic()
        matching=turn_runtime.get('sequence')==turn_sequence and turn_received_at>=turn_started_at
        if (link is None or control_mode.get()!='turn' or not motion_allowed.get()
                or not firmware_confirmed.get() or not sensor_nav_clear
                or now-last_sensor_time>1.6
                or (matching and now-turn_received_at>1.6)
                or (not matching and now-turn_started_at>2.0)):
            reason=("FPGA报告定点旋转停止/异常（F20），已停车；详细原因见本任务Z回传和日志"
                    if last_fault_bits & 0x20 else
                    "旋转许可已撤销：状态/链路/传感器无效或未收到本任务回传")
            stop()
            turn_result.set(reason)
            log(f"TURN END seq={turn_sequence} reason={reason}")
            return
        try:
            link.write(b'G')
        except (serial.SerialException,OSError) as exc:
            fault("旋转续期",exc)
            return
        turn_timer=root.after(100,turn_lease)

    def start_turn(sign: int) -> None:
        nonlocal turn_sequence,turn_timer,turn_enabled,turn_started_at,pose_confirmed
        if turn_enabled:
            turn_result.set(f"任务 #{turn_sequence} 正在执行；无需按住或重复点击，停止S可取消")
            return
        stop()
        if (firmware_name.get() not in ('SIN10','SIN11','SIN12') or link is None
                or not motion_allowed.get() or not firmware_confirmed.get()
                or not sensor_nav_clear or time.monotonic()-last_sensor_time>1.6
                or not turn_received_at or time.monotonic()-turn_received_at>1.6):
            turn_result.set(f"需{args.firmware}有效Z回传、有效IMU/ToF及运动许可；先连接并核对")
            return
        try:
            angle=90.0*sign
            turn_sequence=(turn_sequence+1)&0xffff
            packet=pack_turn_relative(turn_sequence,angle,12,not yaw_ccw_positive.get())
        except (ValueError,TypeError) as exc:
            turn_result.set(str(exc));return
        control_mode.set("turn")
        turn_enabled=True
        pose_confirmed=False
        pose_status.set("旋转后地图航向/位置须重新确认；暂不沿用旧导航状态")
        update_nav_button_state()
        turn_result.set(f"等待中性间隔后发送 #{turn_sequence}，相对角度 {angle:+.1f}°")

        def send_request():
            nonlocal turn_started_at,turn_timer
            turn_timer=None
            if not turn_enabled:return
            if (link is None or control_mode.get()!='turn' or not motion_allowed.get()
                    or not firmware_confirmed.get() or not sensor_nav_clear
                    or time.monotonic()-last_sensor_time>1.6
                    or time.monotonic()-turn_received_at>1.6):
                stop();return
            try:
                link.write(packet)
                log(f"TURN TX seq={turn_sequence} angle={angle:+.2f} inverted={not yaw_ccw_positive.get()}")
                turn_started_at=time.monotonic()
                turn_result.set(f"已写旋转任务 #{turn_sequence}，等待FPGA确认")
                turn_lease()
            except (serial.SerialException,OSError) as exc:
                fault("发送旋转帧",exc)
        turn_timer=root.after(180,send_request)

    def read_pi_mission(launch=False):
        nonlocal mission_read_generation
        expected_id=mission_job.get('mission_id') if launch else None
        if launch and expected_id is None:
            mission_result.set('请先读取Pi任务');return
        stop()
        mission_read_generation+=1
        generation=mission_read_generation
        base=mission_url.get().strip().rstrip('/')
        if not base.startswith(('http://','https://')):
            mission_result.set('请填写Pi的HTTP地址');return
        mission_job.clear()
        allow_search=mission_search_allowed.get()
        mission_result.set('正在读取Pi任务；不会发送运动')
        def worker():
            try:
                with urllib.request.urlopen(base+'/api/status',timeout=3) as response:
                    raw=response.read(65537)
                if len(raw)>65536:raise ValueError('状态响应过大')
                data=json.loads(raw)
                readiness=check_mission_readiness(data,allow_search)
                if launch and data.get('mission_id')!=expected_id:
                    raise ValueError('Pi任务已改变；请重新读取并核对新任务号')
                pack_mission_request(0,data['mission_id'],data['mission_class_id'],
                    data['mission_distance_mm'],data['mission_color'])
                data['_readiness']=readiness
                data['_search_allowed']=allow_search
                mission_reads.put((generation,data,None,launch))
            except Exception as error:mission_reads.put((generation,None,str(error),launch))
        threading.Thread(target=worker,daemon=True).start()

    def poll_mission_reads():
        while not mission_reads.empty():
            generation,data,error,launch=mission_reads.get_nowait()
            if generation!=mission_read_generation:continue
            mission_job.clear()
            if launch and data is not None and data['_search_allowed']!=mission_search_allowed.get():
                error='搜索设置已改变，请重新读取任务';data=None
            if error:mission_result.set('读取失败：'+error)
            else:
                mission_job.update(data)
                mission_result.set(f"Pi任务 #{data['mission_id']:08X} · {data['mission_color']} {target_label(data['mission_class'])} · {data['mission_distance_mm']}mm；尚未启动")
                mission_guidance.set(data['_readiness'])
                log(f"MISSION PREFLIGHT #{data['mission_id']:08X} lock={data.get('task_lock_id',0)} candidates={data.get('mission_candidate_count','unknown')} search={mission_search_allowed.get()}")
                if launch:start_mission_validated()
        root.after(100,poll_mission_reads)

    def mission_lease():
        nonlocal mission_timer,mission_last_lease_at
        mission_timer=None
        if not mission_enabled:return
        now=time.monotonic()
        if mission_last_lease_at and now-mission_last_lease_at>.25:
            gap=now-mission_last_lease_at
            # Tk is not a real-time clock. A266ms UI scheduling gap must not
            # manufacture cancellation before the FPGA's300ms lease expires.
            # M can only renew an already-active task; after expiry it cannot
            # restart one. Sensor/permission/terminal checks below still win.
            mission_link_note.set(f'本机续期延迟{gap:.2f}秒；停车以FPGA租约/状态为准，超时不自动重启')
            log(f'MISSION本机续期延迟 {gap:.3f}s；FPGA{mission_lease_ms(pid_version)}ms租约继续生效，不伪造本机取消')
        matching=(mission_runtime.get('task_id')==mission_job.get('mission_id')
                  and mission_received_at>=mission_started_at)
        if (link is None or control_mode.get()!='mission' or not motion_allowed.get()
                or not firmware_confirmed.get() or not sensor_nav_clear
                or now-last_sensor_time>1.6
                or (matching and not mission_runtime.get('active'))
                or (matching and now-mission_received_at>1.6)
                or (not matching and now-mission_started_at>2.5)):
            stop();mission_result.set('任务许可已撤销：链路/传感器/状态失效；不自动恢复');return
        try:link.write(b'M')
        except (serial.SerialException,OSError) as exc:fault('任务续期',exc);return
        mission_last_lease_at=time.monotonic()
        mission_timer=root.after(100,mission_lease)

    def start_mission():
        # Re-read live perception; a previously read snapshot is not authority.
        read_pi_mission(launch=True)

    def start_mission_validated():
        nonlocal mission_enabled,mission_sequence,mission_timer,mission_started_at,pose_confirmed
        stop()
        if (firmware_name.get() not in ('SIN11','SIN12') or control_mode.get()!='mission' or not mission_job
            or link is None or not firmware_confirmed.get() or not motion_allowed.get()
            or not sensor_nav_clear or time.monotonic()-last_sensor_time>1.6
            or not mission_received_at or time.monotonic()-mission_received_at>1.6):
            mission_result.set(f'需{args.firmware}有效J回传、智能任务模式、Pi任务及有效传感器和运动许可');return
        if mission_runtime.get('task_id')==mission_job['mission_id']:
            mission_result.set('此编号已执行/拒绝；请在Pi准备新任务再读取');return
        mission_sequence=(mission_sequence+1)&0xffff
        packet=pack_mission_request(mission_sequence,mission_job['mission_id'],
            mission_job['mission_class_id'],mission_job['mission_distance_mm'],
            mission_job['mission_color'],not yaw_ccw_positive.get())
        mission_enabled=True;pose_confirmed=False
        mission_link_note.set(f'每100ms续期；当前固件智能任务许可{mission_lease_ms(pid_version)}ms；TX完成不是板端ACK')
        pose_status.set('搜索可能改变航向，旧地图位姿不再有效')
        def send():
            nonlocal mission_timer,mission_started_at
            mission_timer=None
            if not mission_enabled:return
            if (link is None or not sensor_nav_clear or time.monotonic()-last_sensor_time>1.6
                    or control_mode.get()!='mission' or not motion_allowed.get()
                    or not firmware_confirmed.get()):stop();return
            try:
                link.write(packet);mission_started_at=time.monotonic()
                log(f"MISSION TX #{mission_job['mission_id']:08X}")
                mission_result.set('任务已写入；等FPGA确认，Pi/PC不会伪造完成')
                mission_lease()
            except (serial.SerialException,OSError) as exc:fault('发送任务',exc)
        mission_timer=root.after(180,send)

    def refresh_ports() -> None:
        names = [port.device for port in list_ports.comports()]
        port_selector.configure(values=sorted(set(names + [port_name.get()])))
        log("发现串口：" + (", ".join(names) if names else "无"))

    def send_pid() -> None:
        nonlocal pid_pending,pid_deadline,pid_sequence
        if link is None or not pid_received or time.monotonic()-pid_received>2.0:
            pid_status.set('请连接运行R4的FPGA，收到有效K回传后再发送');return
        if pid_pending is not None:
            pid_status.set('正在等待板端确认，请勿重复发送');return
        if (not sync_received or time.monotonic()-sync_received>2.0 or
            sync_runtime.get('command')!=0 or any(abs(v)>1 for v in sync_runtime.get('speeds',())) or
            auto_enabled or mission_enabled or turn_enabled or vision_enabled_ui or follow_active or (gate and gate.held)):
            pid_status.set('请先停止所有任务，待四轮停止后调参');return
        try:
            values=tuple(int(v.get().strip()) for v in (pid_p,pid_i,pid_d))
            pid_sequence=(pid_sequence+1)&0xffff
            packet=pack_pid_config(pid_sequence,*values)
        except ValueError:
            pid_status.set('请输入整数：P/D为0–32，I为0–8');return
        stop();motion_allowed.set(False);nav_allowed.set(False)
        pending=(pid_sequence,values);pid_pending=pending;pid_deadline=time.monotonic()+4.0
        active_link=link
        pid_status.set('已停车；等待发送及FPGA实际参数确认…')
        def transmit():
            nonlocal control_pending
            if link is not active_link or pid_pending!=pending:return
            try:link.write(packet);log(f'PID请求 #{pending[0]:04X} P/I/D={values}；等待K回传')
            except (serial.SerialException,OSError) as exc:fault('PID发送',exc)
        root.after(450,transmit)

    def connect() -> None:
        nonlocal link, gate
        if link is not None:
            return
        name = port_name.get().strip().upper()
        if not name:
            detail.set("请选择蓝牙 COM 口")
            return
        try:
            raw = serial.Serial(name, 9600, bytesize=serial.EIGHTBITS,
                                parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
                                timeout=0, write_timeout=0.5)
            link = AsyncTrackedPort(raw, event_callback=log)
            gate = CommandGate(link)
            gate.set_speed("3")  # S + preset: safe while the driver is disabled.
        except (serial.SerialException, OSError) as exc:
            fault("连接或初始化", exc)
            return
        link_status.set(f"{name} 已打开 · 后台双向串口；TX完成计数不等于FPGA回执")
        detail.set("请核对 FPGA 当前位流；此界面不会自动授权电机试转。")
        log(f"{name} 9600/8N1 已打开；S/速度档已入队，未取得 FPGA 命令 ACK")
        update_nav_button_state()

    def report_manual_control(message: str) -> None:
        # O telemetry is the board state. Keep the last button result separate
        # so a periodic idle O packet cannot erase the reason A was not sent.
        manual_control_feedback.set('操作提示：'+message)
        log('R5 CONTROL RESULT: '+message)

    def send_manual_control(action: str) -> None:
        nonlocal control_pending
        now=time.monotonic()
        if link is None:
            report_manual_control('未发送：请先连接蓝牙COM口');return
        if pid_version<5:
            report_manual_control('未发送：需要R5及以后固件的K/O回传');return
        if now-pid_received>2.0 or not control_received or now-control_received>2.0:
            report_manual_control('未发送：K固件/O避障状态回传已过期，请检查接收');return
        if control_pending is not None:
            report_manual_control('操作等待板端回传，请勿重复点击');return
        if (not sync_received or now-sync_received>2.0 or sync_runtime.get('command')!=0 or
            any(abs(v)>1 for v in sync_runtime.get('speeds',())) or auto_runtime.get('active') or
            auto_enabled or mission_enabled or turn_enabled or vision_enabled_ui or follow_active or (gate and gate.held)):
            report_manual_control('未发送：请先停止所有任务并待四轮静止，确认C同拍回传有效');return
        if action=='A' and (not local_geometry_confirmed.get() or not firmware_confirmed.get() or not sensor_nav_clear):
            missing=[]
            if not local_geometry_confirmed.get():missing.append('未勾选几何/里程/IMU方向核对')
            if not firmware_confirmed.get():missing.append('未勾选当前固件核对')
            if not sensor_nav_clear:missing.append('IMU/ToF无效、硬停或故障未解除')
            report_manual_control('启用未发送：'+'；'.join(missing));return
        if action=='U' and (not control_runtime.get('blocked_mask') or control_runtime.get('severe_mask')):
            report_manual_control('仅可解除纯受阻/无反馈；反向、超速或未知保护需排查后S0');return
        if action=='U' and not last_tof_valid:
            report_manual_control('ToF失效或近障未解除，不能清除受阻状态');return
        stop();motion_allowed.set(False);nav_allowed.set(False)
        active_link=link;control_pending=(action,now+4.5,control_runtime['sequence'],False)
        report_manual_control('已停车；等待发送及板端实际状态确认…')
        def transmit():
            nonlocal control_pending
            if link is not active_link or control_pending is None or control_pending[0]!=action:return
            try:
                link.write(action.encode('ascii'))
                control_pending=(*control_pending[:3],True)
                report_manual_control(f'已发送{action}；等待板端O状态确认，尚未确认生效')
                log(f'R5 CONTROL TX {action}; wait for O sequence')
            except (serial.SerialException,OSError) as exc:fault('R5停车控制',exc)
        root.after(450,transmit)

    def maybe_acknowledge_block():
        nonlocal block_ack_attempted
        now=time.monotonic()
        evidence={w:v['reason'] for w,v in fault_snapshots.items()
                  if fault_evidence_at.get(w,0)>=block_episode_at and now-fault_evidence_at.get(w,0)<8.0}
        idle=not (auto_runtime.get('active') or auto_enabled or mission_enabled or turn_enabled
                  or vision_enabled_ui or follow_active or (gate and gate.held))
        if link is not None and can_acknowledge_block(version=pid_version,attempted=block_ack_attempted,
                pending=control_pending is not None,
                fault_bits=last_fault_bits if last_wheel_fault_mask==control_runtime.get("blocked_mask") else 0,
                blocked=control_runtime.get('blocked_mask',0),severe=control_runtime.get('severe_mask',0),
                fresh=all(t>0 and now-t<1.6 for t in (pid_received,control_received,sync_received,last_sensor_time)),
                command=sync_runtime.get('command'),speeds=sync_runtime.get('speeds',()),idle=idle,
                sensors_clear=last_imu_valid and last_tof_valid and last_distance_mm>100 and not(last_fault_bits & 0x07),
                evidence=evidence):
            block_ack_attempted=True
            log('纯E1：自动停车确认一次；保留快照，不自动重新授权或运动')
            send_manual_control('U')

    def connect_sensor() -> None:
        nonlocal sensor_link
        if sensor_link is not None:
            return
        name = sensor_port_name.get().strip().upper()
        try:
            sensor_link = TrackedPort(serial.Serial(
                name, 115200, bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
                timeout=0, write_timeout=0.2))
            sensor_status.set(f"{name} 已打开 · 115200/8N1")
            log(f"{name} 115200/8N1 已打开；等待 I/T/D/H 状态")
        except (serial.SerialException, OSError) as exc:
            sensor_link = None
            sensor_status.set(f"{name} 打开失败：{exc}")

    def disconnect_sensor() -> None:
        nonlocal sensor_link, sensor_via_link, sensor_nav_clear, last_sensor_time
        if sensor_link is not None:
            try:
                sensor_link.close()
            except (serial.SerialException, OSError):
                pass
        sensor_link = None
        sensor_via_link = False
        sensor_nav_clear = False
        last_sensor_time = 0.0
        sensor_status.set("传感器串口未连接")
        tof_display.set("ToF：未连接")
        imu_display.set("IMU：未连接")
        fault_display.set("FPGA 告警：未收到状态")
        update_nav_button_state()

    def disconnect() -> None:
        stop()
        close_link()
        link_status.set("蓝牙已断开")
        detail.set("试转许可已清除；如车辆仍运动，立即关闭驱动板 12 V。")

    def select_speed(preset: str) -> None:
        if gate is None:
            detail.set("先连接蓝牙 COM 口")
            return
        cancel_repeat()
        try:
            gate.set_speed(preset)
        except (serial.SerialException, OSError) as exc:
            fault("调速", exc)
            return
        counts = {"1": 12, "2": 16, "3": 20}[preset]
        detail.set(f"S + {preset} 已本地写入；目标 {counts} 计数/10 ms，停车后重新按方向键。")

    def update_nav_button_state() -> None:
        live_sensor_clear = (
            (sensor_link is not None or sensor_via_link) and sensor_nav_clear
            and time.monotonic() - last_sensor_time < 1.6
        )
        can_send = bool(
            link is not None and len(route) > 1 and firmware_confirmed.get()
            and nav_allowed.get() and control_mode.get() == "nav"
            and btd6_nav_supported(firmware_name.get()) and not (last_fault_bits & 0x10)
            and live_sensor_clear and pose_confirmed
        )
        send_goal_button.configure(state="normal" if can_send else "disabled")
        # Stopping must remain available even after navigation permission is
        # revoked by a fault, a stale sensor frame, or an operator action.
        stop_nav_button.configure(state="normal" if link is not None else "disabled")

    def send_goal_to_fpga() -> None:
        nonlocal nav_sequence, pose_confirmed
        if last_fault_bits & 0x10:
            nav_status.set("FPGA 已锁存电机 PI 故障；检查 12 V/编码器并在安全状态下按 S0 复位后再授权导航")
            return
        if len(route) < 2 or goal is None:
            nav_status.set("请先在地图选择可达终点")
            return
        if not pose_confirmed:
            nav_status.set("当前位置未确认；停车后在地图左侧确认当前格，再重新预览")
            return
        if control_mode.get() != "nav":
            nav_status.set("请先切换到自动导航模式")
            return
        if not link or not firmware_confirmed.get() or not nav_allowed.get():
            nav_status.set("需连接蓝牙、核对当前固件并勾选“允许自主导航”")
            return
        if not btd6_nav_supported(firmware_name.get()):
            nav_status.set("当前固件不支持导航帧：已锁定，避免旧固件误动作")
            return
        if not ((sensor_link is not None or sensor_via_link) and sensor_nav_clear
                and time.monotonic() - last_sensor_time < 1.6):
            nav_status.set("传感器状态无效、硬停或超过 1 秒未刷新；未发送导航路径")
            return
        try:
            # 先发 S 清除手动模式，再发 CRC 完整的路径帧；路径由 GUI 规划，FPGA 逐格执行。
            if gate is not None:
                gate.stop()
            nav_sequence = (nav_sequence + 1) & 0xFFFF
            frame = pack_btd6_route(nav_sequence, route, goal[0], goal[1])
            link.write(frame)
        except (serial.SerialException, OSError, ValueError) as exc:
            fault("发送 FPGA 导航终点", exc)
            return
        directions = route_directions(route)
        pose_confirmed = False
        pose_status.set("路径已写出；运动后当前位置未知，再次发送前须人工确认")
        update_nav_button_state()
        nav_status.set(f"已写入 BTD6 路径帧 seq={nav_sequence}；路径 {len(route)-1} 步；等待 FPGA 编码器执行")
        detail.set(f"串口已写入路径帧（当前固件没有 ACK，尚不能确认 FPGA 接收）；方向序列预览 {directions[:32]}{'…' if len(directions) > 32 else ''}")
        log(f"NAV TX: path goal=({goal[0]},{goal[1]}) seq={nav_sequence} steps={len(route_codes(route))} bytes={len(frame)}")

    def stop_navigation() -> None:
        if gate is None:
            nav_status.set("蓝牙未连接")
            return
        try:
            gate.stop()
        except (serial.SerialException, OSError) as exc:
            fault("停止 FPGA 导航", exc)
            return
        nav_status.set("已发送 S：停止手动/导航输出；FPGA 看门狗仍会停车")
        log("NAV STOP: S")

    def consume_bluetooth_sensor(fields, source="蓝牙 COM9", raw_line="") -> None:
        nonlocal sensor_via_link, sensor_nav_clear, last_sensor_time
        nonlocal last_imu_valid, last_tof_valid, last_distance_mm, last_yaw_deg, last_fault_bits
        nonlocal obstacle_latched, pi_fault_latched_ui, block_ack_attempted, block_episode_at, last_wheel_fault_mask
        sensor_via_link = source == "蓝牙 COM9"
        imu_ok, tof_ok, distance, hard_stop, faults, roll, pitch, yaw, wheel_fault = fields
        last_sensor_time = time.monotonic()
        sensor_nav_clear = bool(
            imu_ok == '1' and tof_ok == '1' and hard_stop == '0'
            and faults is not None and int(faults, 16) == 0
            and wheel_fault is not None and int(wheel_fault, 16) == 0
        )
        distance_mm = int(distance)
        last_imu_valid = imu_ok == '1'
        last_tof_valid = tof_ok == '1' and hard_stop == '0'
        last_distance_mm = distance_mm
        sensor_status.set(
            source + " · " +
            f"IMU {'有效' if imu_ok == '1' else '无效'} · "
            f"ToF {'有效' if tof_ok == '1' else '无效'} · "
            f"距离 {distance_mm} mm · {'硬停车' if hard_stop == '1' else '可通行'}")
        tof_display.set(
            f"ToF 前方：{distance_mm} mm · "
            f"{'硬停 ≤100 mm' if firmware_name.get() in ('SIN7', 'SIN8', 'SIN9', 'SIN10', 'SIN11', 'SIN12') and hard_stop == '1' else '硬停 ≤250 mm' if hard_stop == '1' else '减速区' if distance_mm < 800 else '通行区'}"
            if tof_ok == '1' else "ToF 前方：数据无效，禁止行驶")
        if imu_ok == '1' and roll and pitch and yaw:
            angles = [math.degrees(struct.unpack('>f', bytes.fromhex(value))[0])
                      for value in (roll, pitch, yaw)]
            if all(math.isfinite(value) and abs(value) <= 360 for value in angles):
                last_yaw_deg = angles[2]
                imu_display.set(
                    f"IMU 姿态：横滚 {angles[0]:+.1f}° · "
                    f"俯仰 {angles[1]:+.1f}° · 偏航 {angles[2]:+.1f}°")
            else:
                last_imu_valid = False
                imu_display.set("IMU 姿态：帧已接收，但数值异常")
        else:
            last_imu_valid = False
            imu_display.set("IMU 姿态：尚无有效姿态帧；检查 B17、共地和 115200 波特率")
        if faults is not None:
            bits = int(faults, 16)
            last_fault_bits = bits
            reasons = [label for bit, label in ((0, "ToF保护停车"), (1, "蓝牙超时停车"),
                       (2, "蓝牙帧错误"), (3, "导航停止/异常"), (4, "运动已暂停"), (5, "定点旋转停止/异常"))
                       if bits & (1 << bit)]
            if bits & 0x10 and wheel_fault is not None:
                wheel_bits = int(wheel_fault, 16)
                last_wheel_fault_mask=wheel_bits
                wheel_names = [f"M{index + 1}" for index in range(4)
                               if wheel_bits & (1 << index)]
                reasons.append("保护轮：" + ("、".join(wheel_names) if wheel_names else "状态不一致"))
                if control_received and time.monotonic()-control_received<2.0 and control_runtime.get('blocked_mask')==wheel_bits and not control_runtime.get('severe_mask'):
                    reasons.append('受阻停机；停稳后自动确认解除，不自动重启')
                else:reasons.append('等待故障快照确认原因；排查12V、编码器和卡阻')
            fault_display.set("FPGA 状态：" + ("、".join(reasons) if reasons else "正常"))
            if bits & 0x10 and not pi_fault_latched_ui:
                # 断开 12 V 时发送运动命令会因无编码器反馈触发此故障。
                # Pure E1 may be acknowledged while stopped; no motion is restarted.
                stop()
                motion_allowed.set(False)
                nav_allowed.set(False)
                control_mode.set("safe")
                nav_status.set("运动保护停机：行驶授权已撤销；请核对受阻/编码器/供电原因")
                detail.set("连续无反馈可能来自卡轮或12V关闭；先排除原因。纯受阻停稳后自动确认解除，仍须重新授权再运行；反向/超速或旧固件需排查后S0复位。")
                block_ack_attempted=False
                block_episode_at=time.monotonic()
                pi_fault_latched_ui = True
                update_nav_button_state()
            elif not (bits & 0x10) and pi_fault_latched_ui:
                pi_fault_latched_ui = False
                control_mode.set("manual")
                fault_snapshots.clear()
                motor_fault_evidence.set('电机故障快照：已复位；历史证据保存在日志文件')
                detail.set("板端保护已解除；排除卡阻后重新勾选运动许可，再按方向运行。")
        else:
            fault_display.set("FPGA 告警：旧版状态帧未提供故障来源")
        if raw_line:
            log(source + " 传感器 RX: " + raw_line)
        update_nav_button_state()
        if hard_stop == '1':
            if not obstacle_latched and control_mode.get() == "nav":
                stop_navigation()
                nav_status.set(
                    f"{'ToF 数据失效' if tof_ok != '1' else f'ToF 检测到 {int(distance)} mm 近障'}"
                    "，FPGA 已停车；确认位置与障碍后才可重新规划下发")
            elif not obstacle_latched and control_mode.get() in ("manual", "follow", "turn"):
                # ToF 硬停可能先触发 FPGA 蓝牙看门狗锁存；主动发 S
                # 清除该锁存，但不在障碍物撤离时自动恢复运动。
                stop()
                detail.set(
                    f"{'ToF 数据失效' if tof_ok != '1' else f'ToF 检测到 {int(distance)} mm 近障'}"
                    "，已发送 S；恢复有效且通行后请重新点击方向")
            obstacle_latched = True
        else:
            if obstacle_latched:
                nav_status.set("ToF 障碍已撤离；车辆保持停止，请重新下发方向")
            obstacle_latched = False

    def poll_serial_once() -> None:
        nonlocal auto_runtime,auto_received
        nonlocal mission_runtime,mission_received_at
        nonlocal turn_runtime,turn_received_at
        nonlocal obstacle_latched, pi_fault_latched_ui, last_fault_bits
        nonlocal block_ack_attempted, block_episode_at
        nonlocal sensor_nav_clear, last_sensor_time
        nonlocal vision_received_at, vision_runtime
        nonlocal last_imu_valid, last_tof_valid, last_distance_mm, last_yaw_deg
        nonlocal bluetooth_rx_count, bluetooth_rx_at
        nonlocal pid_received,sync_received,sync_runtime,pid_pending,pid_version,control_received,control_runtime,control_pending
        if pid_pending is not None and time.monotonic()>pid_deadline:
            pid_pending=None;pid_status.set('未收到匹配的板端确认；参数是否生效未知，请检查回传')
        if control_pending is not None and time.monotonic()>control_pending[1]:
            control_pending=None;report_manual_control('操作未获板端确认；状态未知，保持停止')
        if link is not None:
            try:
                for line in link.poll_lines():
                    bluetooth_rx_count += 1
                    bluetooth_rx_at = datetime.now().strftime("%H:%M:%S")
                    if len(line) >= 2 and line[0] == "M" and line[1] in "1234":
                        if not sync_received or time.monotonic()-sync_received>2.0:
                            wheel_lines[int(line[1])].set(line)
                        evidence = parse_motor_fault_snapshot(line)
                        if evidence is not None:
                            fault_snapshots[evidence['wheel']] = evidence
                            fault_evidence_at[evidence['wheel']]=time.monotonic()
                            motor_fault_evidence.set('故障瞬间：' + '；'.join(
                                f"M{v['wheel']} {v['reason_text']}，计数{v['speed']:+d}/10ms，占空比请求{v['duty']/10:.1f}%"
                                for _, v in sorted(fault_snapshots.items())))
                    tuning=parse_pid_status(line)
                    if tuning is not None:
                        pid_received=time.monotonic()
                        pid_version=tuning['version']
                        manual_control_version.set(f'板端固件回传：K{pid_version:02X}（R{pid_version}）')
                        actual=f"板端实际 P={tuning['p']} I={tuning['i']} D={tuning['d']}"
                        if pid_pending is not None and tuning['sequence']==pid_pending[0]:
                            expected=pid_pending[1];pid_pending=None
                            if tuning['status']==1 and tuple(tuning[k] for k in ('p','i','d'))==expected:
                                pid_status.set('已确认生效：'+actual+'；运动许可已撤销')
                            else:pid_status.set('板端拒绝/不一致：'+{2:'仍在运动',3:'参数越界'}.get(tuning['status'],'状态异常')+'；'+actual)
                        elif pid_pending is None and (tuning['status']==0 or not pid_status.get().startswith(('已确认生效','板端拒绝'))):pid_status.set(actual+'（四轮共用；复位恢复4/1/0）')
                    safety=parse_control_status(line)
                    if safety is not None:
                        control_runtime=safety;control_received=time.monotonic()
                        text=manual_avoid_status_text(safety)
                        if (control_pending is not None and control_pending[3] and
                            safety['sequence']==((control_pending[2]+1)&255)):
                            action=control_pending[0]
                            if safety['recovery_result']==2:
                                control_pending=None;report_manual_control('板端拒绝操作，请核对停车/传感器/故障类别')
                            elif (action=='A' and safety['avoid_enabled']) or (action=='a' and not safety['avoid_enabled']):
                                control_pending=None;report_manual_control('已获板端确认：'+('避障已启用' if action=='A' else '避障已关闭')+'；运动许可仍关闭')
                            elif action=='U' and safety['recovery_result']==1 and safety['blocked_mask']==0:
                                control_pending=None;report_manual_control('受阻已解除，运动许可仍关闭')
                            elif action=='U' and safety['recovery_result']==2:
                                control_pending=None;report_manual_control('板端拒绝解除，请检查停车/传感器/故障类别')
                        manual_avoid_status.set(text)
                    common=parse_wheel_sample(line)
                    if common is not None:
                        sync_runtime=common;sync_received=time.monotonic()
                        sync_status.set(f"同拍#{common['sequence']:04X} · {'锁向' if common['heading_locked'] else '未锁向'} "
                            f"参考{common['reference_deg']:+.1f}° 误差{common['error_deg']:+.1f}° 修正{common['correction']:+d}")
                        for k in range(4):
                            wheel_lines[k+1].set(f"M{k+1} 同拍#{common['sequence']:04X} T{common['targets'][k]:03d} "
                                f"A{common['speeds'][k]:+04d} D{common['duties'][k]:04d}")
                        if common['command'] in (5,6):
                            signs=(-1,1,-1,1) if common['command']==5 else (1,-1,1,-1)
                            wheels=[v*sign for v,sign in zip(common['speeds'],signs)]
                            vx=sum(wheels)/4;vy=(-wheels[0]+wheels[1]+wheels[2]-wheels[3])/4
                            sync_status.set(f"同拍#{common['sequence']:04X} · 旋转平移残差 X={vx:+.1f} Y={vy:+.1f}计数/10ms")
                    fields = parse_sensor_status(line)
                    if fields is not None:
                        consume_bluetooth_sensor(fields, "蓝牙 COM9", line)
                    vision = parse_vision_status(line)
                    if vision is not None:
                        vision_runtime = vision
                        vision_received_at = time.monotonic()
                        states = {0:"停止",1:"未选目标",2:"已锁定·等待许可",3:"目标丢失/未确认",4:"向左对准",5:"向右对准",6:"接近目标",7:"保持20cm",8:"近障停车",9:"视觉超时",10:"电机故障",11:"换向中性等待"}
                        vision_status.set(
                            f"数字{follow_origin_digit['digit']} #{follow_origin_digit['lock_id']}已触发ToF；当前图像仅供观察，不控制左右或续行"
                            if follow_origin_digit is not None else
                            f"FPGA锁定：{vision['class_name']} #{vision['lock_id']} · "
                            f"{'目标可见' if vision['visible'] else '丢失/未确认'} · "
                            f"{states.get(vision['state'],'未知')} · {'执行中 A1' if vision['active'] else '停止 A0'}")
                    auto=parse_autonav_status(line)
                    if auto is not None:
                        previous_auto=auto_runtime
                        auto_runtime=auto;auto_received=time.monotonic()
                        reply=map_navigation_reply(auto,auto_request_context)
                        if reply not in ('unrelated','goal_mismatch','mode_mismatch'):
                            auto_map_runtime.update(auto)
                        if auto_enabled and reply=='active' and not auto_request_context.get('confirmed'):
                            auto_request_context['confirmed']=True
                            auto_result.set(f"板端已确认终点{auto_request_context['goal']} #{auto_sequence}；紫色估仅表示当前位置推算，不是目的地")
                            log(f'AUTONAV GOAL ACK seq={auto_sequence} goal={auto_request_context["goal"]}')
                        prefix='普通前进局部避障' if auto.get('local_mode') else 'FPGA导航'
                        position_text="" if auto.get("local_mode") else f" · 当前估计({auto['x']},{auto['y']})"
                        destination="" if auto.get('local_mode') else f" · 板端终点({auto['gx']},{auto['gy']})"
                        ox,oy=auto['obstacle']
                        obstacle_text=(f" · ToF/里程推算障碍({ox},{oy})，非实测场地坐标"
                            if not auto.get('local_mode') and 0<=ox<20 and 0<=oy<20 else '')
                        auto_status.set(f"{prefix} #{auto['sequence']} · {auto['state_name']}{position_text}{destination}{obstacle_text} · 重规划{auto['replans']}次 · 原因:{auto['reason_name']}")
                        ox,oy=auto['obstacle']
                        point=navigation_obstacle_point(auto,auto_request_context,version=pid_version,
                            capability_fresh=bool(pid_received and 0<=time.monotonic()-pid_received<=2.0))
                        generation=(auto['sequence'],auto['replans'])
                        if point is not None and generation not in measured_generations:
                            measured_generations.add(generation);measured_cells.add(point[1]*GRID+point[0])
                            map_observation_status.set(f'本次停稳ToF投影格{point} · 起点/航向/探头退后量参与换算；黄色为测点，不是车辆位置')
                            log(f'AUTONAV MAP POINT seq={auto["sequence"]} replan={auto["replans"]} cell={point} firmware=R{pid_version}')
                        elif pid_version not in (19,20):
                            map_observation_status.set(f'当前R{pid_version}：旧障碍坐标仅见N回传文字，不画为新测点；10cm左1前3右1需R19/K13')
                        if measured_cells and reply == 'stopped':
                            map_observation_status.set('历史测点：来自刚才已停止的任务，不是当前新测量；重新确认位置后再标定。')
                        draw_map()
                        if auto.get('local_mode') and previous_auto.get('local_mode') and previous_auto.get('active') and not auto['active']:
                            continuing=continue_local_forward(previous_auto,auto,version=pid_version,
                                capability_fresh=time.monotonic()-pid_received<2.0,held=gate.held if gate else None,
                                mode=control_mode.get(),permitted=motion_allowed.get() and firmware_confirmed.get())
                            if not continuing:
                                # A local task ending cancels its motion, not the
                                # operator's checked permission. Actual faults,
                                # disconnects and explicit unchecking still stop
                                # and revoke permission through their own paths.
                                stop()
                                detail.set('局部避障已停止；运动许可保持原状态，需要继续时请重新按方向。')
                        if auto_enabled and auto_received>=auto_started and reply!='unrelated':
                            request_goal=auto_request_context['goal']
                            if reply in ('goal_mismatch','mode_mismatch','invalid_completion'):
                                stop();auto_result.set(f"导航结束：板端终点/到达回执不一致，未判定到达；已发送{request_goal}，板端({auto['gx']},{auto['gy']})")
                                log(f'AUTONAV REPLY REJECTED {reply}: request={auto_request_context} reply={auto}')
                            elif reply=='arrived':
                                stop();auto_result.set(f"导航结束：FPGA确认到达已发送终点{request_goal}并停稳；位置仍为编码器估计，请核对实车")
                            elif reply=='stopped':
                                stop();auto_result.set(f"导航结束：未到达已发送终点{request_goal}；{auto['reason_name']}；停止锁存")
                    job=parse_mission_status(line)
                    if job is not None:
                        mission_runtime=job
                        mission_received_at=time.monotonic()
                        mission_status.set(f"FPGA #{job['task_id']:08X} · {job['state_name']} · 锁定#{job['lock_id']} · 扫描方向{job['leg']+1}/4")
                        goal_mm=mission_job.get('mission_distance_mm',200)
                        if job['active'] and job['state']==3 and last_distance_mm<=goal_mm+25:
                            mission_guidance.set('距离已进入到达区：平移停止，等待目标在画面中央；尚未完成')
                        elif job['active'] and job['state']==3:
                            mission_guidance.set('正在左右横移对准；R12分段对准/接近后停稳观察，测距跳变先等待，保持同一目标可见')
                        elif job['active'] and job['state']==16:
                            mission_guidance.set('已停车持续识别原数字，重新确认后自动继续原任务，无需重新发送；S/通信及硬件保护仍有效'
                                if pid_version>=14 else '旧R13短暂漏检等待最多4秒；此固件不支持持续找回')
                        elif job['active'] and job['state']==17:
                            mission_guidance.set('原数字短角度左右搜索中；锁定号与任务不变，发现原数字立即停转，重新确认后继续原任务')
                        elif job['state']==15:
                            mission_guidance.set('本段横移累计偏航超过8°已停止；核对车轮/相机方向，重新准备任务，不自动续跑')
                        elif job['state']==8:
                            mission_guidance.set(f'FPGA运动许可超时（当前固件{mission_lease_ms(pid_version)}ms）：查看TX完成/驱动耗时；这不是60秒任务总超时')
                        elif job['state']==6:
                            mission_guidance.set('FPGA已确认目标居中、距离稳定，任务完成并保持停止')
                        if mission_enabled and job['task_id']==mission_job.get('mission_id') and not job['active']:
                            stop()
                            mission_result.set(f"任务 #{job['task_id']:08X}：{job['state_name']}；已停止，重试须准备新任务")
                    turn=parse_turn_status(line)
                    if turn is not None:
                        turn_runtime=turn
                        turn_received_at=time.monotonic()
                        states={0:'空闲',1:'旋转中',2:'到角稳定中',3:'到角完成',4:'蓝牙许可超时',
                                5:'旋转总超时',6:'传感器/近障/电机故障',7:'启动条件未满足',8:'其他模式取消'}
                        name=states.get(turn['state'],'未知')
                        turn_status.set(f"FPGA旋转 #{turn['sequence']} · {name} · "
                            f"当前{turn['yaw_deg']:+.1f}° / 目标{turn['target_deg']:+.1f}° / 误差{turn['error_deg']:+.1f}°")
                        if (turn_enabled and turn['sequence']==turn_sequence and not turn['active']):
                            stop()
                            control_mode.set("manual")
                            turn_result.set(f"任务 #{turn['sequence']}：{name}，已发送S；需重新操作才可启动")
                            log(f"TURN END seq={turn['sequence']} state={turn['state']} reason={name}")
                    log("RX: " + line)
                tx_status.set(f"TX {link.tx_bytes} 字节 · RX {bluetooth_rx_count} 行 · 最近接收 {bluetooth_rx_at} · 命令无 ACK")
            except (serial.SerialException, OSError) as exc:
                fault("读取遥测", exc)
        if sensor_link is not None:
            try:
                for line in sensor_link.poll_lines():
                    fields = parse_sensor_status(line)
                    if fields is None:
                        log("传感器 RX: " + line)
                        continue
                    consume_bluetooth_sensor(fields, "有线 COM6", line)
            except (serial.SerialException, OSError) as exc:
                sensor_status.set(f"传感器串口读取失败：{exc}")
                disconnect_sensor()
        if follow_origin_digit is None and vision_received_at and time.monotonic()-vision_received_at > 1.6:
            vision_status.set("FPGA 锁定回传超时：请检查蓝牙；不再沿用旧目标状态")
            if vision_enabled_ui:
                stop()
        maybe_acknowledge_block()
        update_nav_button_state()

    def poll_serial() -> None:
        nonlocal sensor_nav_clear
        try:
            poll_serial_once()
        except Exception as exc:
            # An unexpected display/parser failure must revoke motion and stay
            # visible; it must not silently kill every subsequent RX callback.
            import traceback
            traceback.print_exc()
            sensor_nav_clear = False
            motion_allowed.set(False)
            nav_allowed.set(False)
            stop()
            link_status.set("接收处理异常 · 已撤销行驶许可")
            detail.set(f"{type(exc).__name__}: {exc}；接收轮询继续，需处理错误后重新授权")
            log("RX 处理异常: " + type(exc).__name__ + ": " + str(exc))
        finally:
            root.after(80, poll_serial)

    def on_close() -> None:
        stop()
        close_link()
        root.destroy()

    header = tk.Frame(root)
    header.pack(fill="x", padx=12, pady=(10, 5))
    tk.Label(header, text="统一驾驶台", font=("Microsoft YaHei UI", 17, "bold")).pack(side="left")
    tk.Label(header, text=f"{args.firmware} · 蓝牙四轮/IMU/ToF/视觉 · USB供树莓派使用",
             fg="#a12b25").pack(side="left", padx=18)
    tk.Button(header, text="停止 S", command=stop, bg="#ffdddd", width=12).pack(side="right")
    live_status = tk.Frame(root)
    live_status.pack(fill="x", padx=16, pady=(0, 5))
    tk.Label(live_status, textvariable=link_status, fg="#075985", anchor="w").pack(fill="x")
    tk.Label(live_status, textvariable=tx_status, fg="#555555", anchor="w").pack(fill="x")
    body = tk.Frame(root)
    body.pack(fill="both", expand=True, padx=12)
    map_panel = ScrollPanel(body, width=478)
    map_panel.pack(side="left", fill="y", padx=(0, 10))
    map_panel.pack_propagate(False)
    left = tk.LabelFrame(map_panel.inner, text="2×2 米地图 · 点选终点 / 路径预览")
    left.pack(fill="both", expand=True)
    if args.firmware=='SIN12':
        tk.Label(left,name='sin12_preview_alignment',
                 text='BFS预览：上→左→下→右；遇障后由板端重规划',
                 wraplength=440,justify='left',anchor='w',fg='#075985').pack(fill='x',padx=8,pady=(4,0))
    canvas = tk.Canvas(left, width=CANVAS_SIZE, height=CANVAS_SIZE, bg="#13283a", highlightthickness=0)
    canvas.pack(padx=8, pady=8)
    canvas.bind("<Button-1>", map_click)
    pid_panel=tk.LabelFrame(left,text='四轮速度PID蓝牙调试 · R4及以后实际参数')
    pid_panel.pack(fill='x',padx=8,pady=(0,6))
    pid_row=tk.Frame(pid_panel);pid_row.pack(fill='x',padx=5,pady=4)
    for label,var in (('P',pid_p),('I',pid_i),('D',pid_d)):
        tk.Label(pid_row,text=label).pack(side='left',padx=(4,2))
        tk.Entry(pid_row,textvariable=var,width=5).pack(side='left')
    tk.Button(pid_row,text='发送PID',command=send_pid).pack(side='left',padx=7)
    tk.Label(pid_panel,textvariable=pid_status,wraplength=430,justify='left',anchor='w',fg='#075985').pack(fill='x',padx=5)
    tk.Label(pid_panel,textvariable=sync_status,wraplength=430,justify='left',anchor='w').pack(fill='x',padx=5,pady=(2,5))
    local_panel=tk.LabelFrame(left,text='普通前进避障 / 受阻处理')
    local_panel.pack(fill='x',padx=8,pady=(0,6))
    tk.Label(local_panel,text='仅车头ToF覆盖；遇障后停稳、转向扫描、局部规划。需持续按前进维持许可，松开即停。R6绕过后继续前进，不设行程终点；R5仍在局部终点停车。后退/横移不宣称已覆盖。',wraplength=430,justify='left').pack(fill='x',padx=5)
    tk.Checkbutton(local_panel,text='已核对ToF安装、IMU转向及里程参数（R18/R19/R20每10cm为500计数；R16/R17为333，旧版1000）',variable=local_geometry_confirmed,wraplength=400,justify='left').pack(anchor='w',padx=5)
    local_row=tk.Frame(local_panel);local_row.pack(fill='x',padx=5,pady=4)
    tk.Button(local_row,text='启用前进避障',command=lambda:send_manual_control('A')).pack(side='left')
    tk.Button(local_row,text='关闭前进避障',command=lambda:send_manual_control('a')).pack(side='left',padx=4)
    tk.Button(local_row,text='解除受阻',command=lambda:send_manual_control('U')).pack(side='left')
    tk.Label(local_panel,textvariable=manual_avoid_status,wraplength=430,justify='left',anchor='w').pack(fill='x',padx=5,pady=3)
    tk.Label(local_panel,textvariable=manual_control_feedback,wraplength=430,justify='left',anchor='w',fg='#9a3412').pack(fill='x',padx=5,pady=3)
    tk.Label(local_panel,textvariable=manual_control_version,wraplength=430,justify='left',anchor='w',fg='#075985').pack(fill='x',padx=5,pady=3)
    coords = tk.Frame(left)
    coords.pack(fill="x", padx=8)
    gx, gy = tk.StringVar(), tk.StringVar()
    for label, var in (("X", gx), ("Y", gy)):
        tk.Label(coords, text=label).pack(side="left", padx=(5, 2))
        tk.Entry(coords, textvariable=var, width=5).pack(side="left")
    tk.Button(coords, text="预览终点", command=input_goal).pack(side="left", padx=7)
    position_row = tk.Frame(left)
    position_row.pack(fill="x", padx=8, pady=(5, 0))
    cx = tk.StringVar(value=str(current_cell[0]))
    cy = tk.StringVar(value=str(current_cell[1]))
    for label, var in (("当前格 X", cx), ("Y", cy)):
        tk.Label(position_row, text=label).pack(side="left", padx=(5, 2))
        tk.Entry(position_row, textvariable=var, width=5).pack(side="left")
    tk.Button(position_row, text="人工确认当前位置", command=confirm_position).pack(side="left", padx=6)
    obstacle_row = tk.Frame(left)
    obstacle_row.pack(fill="x", padx=8, pady=(5, 0))
    ox, oy = tk.StringVar(), tk.StringVar()
    for label, var in (("新障碍 X", ox), ("Y", oy)):
        tk.Label(obstacle_row, text=label).pack(side="left", padx=(5, 2))
        tk.Entry(obstacle_row, textvariable=var, width=5).pack(side="left")
    tk.Button(obstacle_row, text="标记", command=mark_obstacle).pack(side="left", padx=3)
    tk.Button(obstacle_row, text="清除临时障碍", command=clear_obstacles).pack(side="left", padx=3)
    tk.Label(left, textvariable=pose_status, fg="#a12b25", wraplength=450,
             justify="left", anchor="w").pack(fill="x", padx=12, pady=(5, 0))
    tk.Label(left, textvariable=selected_goal, anchor="w").pack(fill="x", padx=12, pady=(7, 0))
    tk.Label(left, textvariable=preview_status, fg="#075985", wraplength=450,
             justify="left", anchor="w").pack(fill="x", padx=12, pady=(4, 7))
    right = tk.Frame(body)
    right.pack(side="left", fill="both", expand=True)
    split = tk.PanedWindow(right, orient="vertical", sashwidth=8, sashrelief="raised")
    split.pack(fill="both", expand=True)
    controls = ScrollPanel(split)
    telemetry = tk.Frame(split)
    split.add(controls, minsize=140, stretch="always")
    split.add(telemetry, minsize=205, height=250, stretch="never")
    connection = tk.LabelFrame(controls.inner, text="蓝牙 COM9 · 手动控制（操作区可滚动）")
    connection.pack(fill="x")
    port_row = tk.Frame(connection)
    port_row.pack(fill="x", padx=9, pady=7)
    port_selector = ttk.Combobox(port_row, textvariable=port_name, width=13)
    port_selector.pack(side="left")
    tk.Button(port_row, text="刷新端口", command=refresh_ports).pack(side="left", padx=4)
    tk.Button(port_row, text="连接", command=connect).pack(side="left", padx=4)
    tk.Button(port_row, text="断开", command=disconnect).pack(side="left", padx=4)
    sensor_row = tk.Frame(connection)
    sensor_row.pack(fill="x", padx=9, pady=(2, 0))
    tk.Label(sensor_row, text="备用有线串口（传感器默认由蓝牙回传）").pack(side="left")
    ttk.Combobox(sensor_row, textvariable=sensor_port_name, values=("COM6",), width=8).pack(side="left", padx=4)
    tk.Button(sensor_row, text="连接传感器", command=connect_sensor).pack(side="left", padx=3)
    tk.Button(sensor_row, text="断开", command=disconnect_sensor).pack(side="left", padx=3)
    tk.Label(connection, textvariable=sensor_status, fg="#075985", anchor="w").pack(fill="x", padx=10)
    tk.Label(connection, textvariable=tof_display, fg="#075985", anchor="w").pack(fill="x", padx=10)
    tk.Label(connection, textvariable=imu_display, fg="#075985", anchor="w").pack(fill="x", padx=10)
    tk.Label(connection, textvariable=fault_display, fg="#a12b25", anchor="w").pack(fill="x", padx=10)
    firmware_row = tk.Frame(connection)
    firmware_row.pack(fill="x", padx=7)
    tk.Label(firmware_row, text=f"固定固件配置：{args.firmware} · 切模式不换固件", name="fixed_firmware",
             fg="#075985").pack(side="left")
    tk.Checkbutton(connection, text="已核对 FPGA 当前运行固件", variable=firmware_confirmed,
                   command=lambda: (stop() if not firmware_confirmed.get() else None,
                                    update_nav_button_state())).pack(anchor="w", padx=7)
    tk.Checkbutton(connection, text="四轮离地或已核对落地测试场地，允许运动（取消即发送 S）", variable=motion_allowed,
                   command=lambda: stop() if not motion_allowed.get() else None).pack(anchor="w", padx=7)
    mode_row = tk.Frame(connection)
    mode_row.pack(fill="x", padx=7, pady=(2, 0))
    tk.Label(mode_row, text="控制模式").pack(side="left")
    modes = (("手动", "manual"), ("板内规划绕障", "autonav"), ("距离跟随", "follow"),
             ("指定目标跟随", "vision"), ("智能任务", "mission"), ("安全停车", "safe"))
    if args.firmware != 'SIN12':
        modes = (("手动", "manual"), ("旧版路径执行", "nav")) + modes[1:]
    for index, (label, value) in enumerate(modes):
        if index == 3:
            mode_row = tk.Frame(connection)
            mode_row.pack(fill="x", padx=7)
        tk.Radiobutton(mode_row, text=label, value=value, variable=control_mode,
                       command=mode_changed).pack(side="left", padx=3)
    button_row = tk.Frame(connection)
    button_row.pack(fill="x", padx=7)
    tk.Label(button_row, text="方向操作").pack(side="left")
    tk.Radiobutton(button_row, text="按住运行", value="hold", variable=button_mode).pack(side="left", padx=3)
    tk.Radiobutton(button_row, text="点击锁定/再点停止", value="click", variable=button_mode).pack(side="left", padx=3)
    pad = tk.Frame(connection)
    pad.pack(pady=8)
    for label, command, row, col in (("前 F", "F", 0, 1), ("左横移 L", "L", 1, 0),
                                     ("后 B", "B", 1, 1), ("右横移 R", "R", 1, 2)):
        button = tk.Button(pad, text=label, width=11, height=2)
        button.grid(row=row, column=col, padx=3, pady=3)
        button.bind("<ButtonPress-1>", lambda event, d=command: press(d, source='mouse'))
    def release_direction(event=None) -> None:
        if button_mode.get() == "hold" and gate and gate.held:
            stop()
            log(f"UI RELEASE type={getattr(event, 'type', None)} "
                f"key={getattr(event, 'keysym', None)}")

    root.bind_all("<ButtonRelease-1>", release_direction)
    for key, direction in (("f", "F"), ("b", "B"), ("l", "L"), ("r", "R")):
        root.bind_all(f"<KeyPress-{key}>", lambda event, d=direction: press(d, source='keyboard'))
    root.bind_all("<KeyRelease-f>", release_direction)
    root.bind_all("<KeyRelease-b>", release_direction)
    root.bind_all("<KeyRelease-l>", release_direction)
    root.bind_all("<KeyRelease-r>", release_direction)
    tk.Button(connection, text="停止 S", command=stop, bg="#ffdddd", width=15).pack(pady=4)
    speeds = tk.Frame(connection)
    speeds.pack(pady=(0, 7))
    for label, preset in (("慢 12", "1"), ("中 16", "2"), ("标准 20", "3")):
        tk.Button(speeds, text=label, command=lambda value=preset: select_speed(value)).pack(side="left", padx=3)
    tk.Label(connection, textvariable=detail, wraplength=580, justify="left", fg="#a12b25").pack(fill="x", padx=10, pady=6)

    tasks = tk.LabelFrame(controls.inner, text="自动导航 / 智能任务 · FPGA 执行")
    tasks.pack(fill="x", pady=8)
    task_transport = ('仅起终点经COM9送入FPGA；板内BFS规划、IMU转向、编码器行程及实测障碍重规划。'
                      if args.firmware == 'SIN12' else
                      '完整路径帧经 COM9 送入 FPGA，编码器逐格闭环在 FPGA 内执行。')
    tk.Label(tasks, text=f"地图 ID 0x{spec['map_id']:04X}；{task_transport}", wraplength=560,
             anchor="w").pack(fill="x", padx=10, pady=(6, 2))
    tk.Checkbutton(tasks, text="已核对地图/障碍/12V/姿态，允许自主导航（落地前必须复核）",
                   variable=nav_allowed,
                   command=update_nav_button_state).pack(anchor="w", padx=7)
    task_buttons = tk.Frame(tasks)
    task_buttons.pack(anchor="w", padx=8, pady=(0, 7))
    send_goal_button = tk.Button(task_buttons, text="发送终点到 FPGA", command=send_goal_to_fpga,
                                 state="disabled", bg="#d9f2df")
    if args.firmware != 'SIN12':
        send_goal_button.pack(side="left", padx=3)
    stop_nav_button = tk.Button(task_buttons, text="停止导航 S", command=stop_navigation,
                                state="disabled", bg="#ffdddd")
    stop_nav_button.pack(side="left", padx=3)
    tk.Button(task_buttons, text="距离跟随 20 cm（ToF）", command=start_real_follow,
              bg="#e8ddff").pack(side="left", padx=3)
    tk.Button(tasks, text="允许指定目标跟随（数字确认→ToF）", command=start_visual_execution,
              bg="#cce8ff").pack(anchor="w", padx=11, pady=(0, 4))
    tk.Label(tasks, textvariable=vision_status, fg="#075985", anchor="w", wraplength=560).pack(fill="x", padx=10, pady=3)
    tk.Label(tasks, textvariable=follow_status, fg="#6b21a8", anchor="w").pack(fill="x", padx=10, pady=(0, 3))
    tk.Label(tasks, textvariable=nav_status, fg="#075985", anchor="w").pack(fill="x", padx=10, pady=(0, 7))

    turn_panel=tk.LabelFrame(controls.inner,text="IMU定点旋转 · 当前固定固件执行")
    turn_panel.pack(fill="x",pady=(0,8))
    turn_row=tk.Frame(turn_panel);turn_row.pack(fill='x',padx=8,pady=5)
    tk.Button(turn_row,text='左转90°',command=lambda:start_turn(1)).pack(side='left',padx=4)
    tk.Button(turn_row,text='右转90°',command=lambda:start_turn(-1)).pack(side='left',padx=4)
    tk.Checkbutton(turn_panel,text='IMU安装标定：车体逆时针转动时偏航角增大',
                   variable=yaw_ccw_positive).pack(anchor='w',padx=6)
    tk.Label(turn_panel,textvariable=turn_status,fg='#075985',wraplength=560,justify='left').pack(fill='x',padx=8,pady=3)
    tk.Label(turn_panel,textvariable=turn_result,fg='#6b21a8',wraplength=560,justify='left').pack(fill='x',padx=8,pady=(0,5))

    auto_panel=tk.LabelFrame(controls.inner,text='SIN12 · FPGA内部规划与实测绕障（待离地/地面验收）')
    auto_panel.pack(fill='x',pady=(0,8))
    ar=tk.Frame(auto_panel);ar.pack(fill='x',padx=8,pady=4)
    tk.Label(ar,text='ToF退后量mm（齐平0，突出为负）').pack(side='left')
    tk.Entry(ar,textvariable=auto_setback,width=6,name='tof_setback').pack(side='left')
    tk.Checkbutton(auto_panel,text='已核对20×22cm外廓、ToF实测偏移、当前位置及车头沿地图+Y',
        variable=auto_geometry,command=lambda: stop() if not auto_geometry.get() else None).pack(anchor='w',padx=8)
    tk.Button(auto_panel,text='只发终点 · 启动板内规划绕障',command=start_auto).pack(anchor='w',padx=8,pady=4)
    tk.Label(auto_panel,textvariable=auto_status,fg='#075985',wraplength=560,justify='left').pack(fill='x',padx=8)
    tk.Label(auto_panel,textvariable=auto_result,fg='#6b21a8',wraplength=560,justify='left').pack(fill='x',padx=8,pady=4)
    tk.Label(auto_panel,text='R16前进暂定333计数/10cm、旧版1000；均须落地复核，横移未改。紫色“估”为板内估计格，黄色为ToF/里程推算障碍（非场地真值），蓝线仅参考。偏差不能靠移动地图标记修正。单前向ToF有盲区。',
        fg='#555555',wraplength=560,justify='left').pack(fill='x',padx=8,pady=4)

    mission_panel=tk.LabelFrame(controls.inner,text='任务六 · 主动搜索/接近/完成 · 当前固定固件执行')
    mission_panel.pack(fill='x',pady=(0,8))
    mr=tk.Frame(mission_panel);mr.pack(fill='x',padx=8,pady=4)
    tk.Entry(mr,textvariable=mission_url,width=30).pack(side='left')
    tk.Button(mr,text='读取Pi任务',command=read_pi_mission).pack(side='left',padx=4)
    tk.Button(mr,text='启动智能任务',command=start_mission).pack(side='left',padx=4)
    tk.Checkbutton(mission_panel,text='允许画外主动搜索（需底盘真实旋转；固定离地不勾）',
        variable=mission_search_allowed,command=stop).pack(anchor='w',padx=8)
    tk.Label(mission_panel,textvariable=mission_status,fg='#075985',wraplength=560,justify='left').pack(fill='x',padx=8)
    tk.Label(mission_panel,textvariable=mission_result,fg='#6b21a8',wraplength=560,justify='left').pack(fill='x',padx=8,pady=4)
    tk.Label(mission_panel,textvariable=mission_guidance,fg='#075985',wraplength=560,justify='left').pack(fill='x',padx=8,pady=3)
    tk.Label(mission_panel,textvariable=mission_link_note,fg='#555555',wraplength=560,justify='left').pack(fill='x',padx=8,pady=3)

    diagnostics = tk.LabelFrame(telemetry, text="FPGA 四轮实时回传 · 蓝牙 RX（固定显示）", name="diagnostics")
    diagnostics.pack(fill="x")
    diagnostics.columnconfigure((0, 1), weight=1)
    tk.Label(diagnostics,textvariable=motor_fault_evidence,fg='#a12b25',anchor='w',
             wraplength=520,justify='left').grid(row=0,column=0,columnspan=2,sticky='ew',padx=6)
    for index in range(1, 5):
        tk.Label(diagnostics, textvariable=wheel_lines[index], font=("Consolas", 10),
                 anchor="w").grid(row=1+(index-1)//2, column=(index-1)%2, sticky="ew", padx=6, pady=2)
    tk.Label(telemetry,textvariable=log_location,anchor='w',wraplength=520,fg='#555555').pack(fill='x')
    log_panel = tk.LabelFrame(telemetry, text="蓝牙收发 / 传感器日志 · 可横向和纵向滚动")
    log_panel.pack(fill="both", expand=True, pady=(4, 0))
    log_panel.rowconfigure(0, weight=1)
    log_panel.columnconfigure(0, weight=1)
    history = tk.Text(log_panel, name="serial_history", height=6, width=1,
                      state="disabled", wrap="none", font=("Consolas", 9))
    history.grid(row=0, column=0, sticky="nsew")
    log_y = ttk.Scrollbar(log_panel, orient="vertical", command=history.yview)
    log_y.grid(row=0, column=1, sticky="ns")
    log_x = ttk.Scrollbar(log_panel, orient="horizontal", command=history.xview)
    log_x.grid(row=1, column=0, sticky="ew")
    history.configure(yscrollcommand=log_y.set, xscrollcommand=log_x.set)

    def focus_check() -> None:
        # A click-locked command is intentionally latched until the same
        # direction or S is clicked again. Losing window focus must not
        # cancel it; the 100 ms refresh and FPGA 300 ms link watchdog still
        # stop motion if this process or the Bluetooth link fails. Hold mode
        # remains a dead-man control and stops on focus loss.
        if button_mode.get() == "hold" and gate and gate.held and root.focus_displayof() is None:
            stop()

    root.bind_all("<FocusOut>", lambda event: root.after(20, focus_check))
    root.protocol("WM_DELETE_WINDOW", on_close)
    draw_map()
    poll_serial()
    poll_mission_reads()
    if args.connect:
        root.after(150, connect)
    root.mainloop()


if __name__ == "__main__":
    main()
