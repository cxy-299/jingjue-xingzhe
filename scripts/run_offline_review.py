"""隔离目录中的 ModelSim 自检：不访问串口、不调用下载器，不改变已验收 NAV3 位流。"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from scripts.build_nav_map import load_map, occupied_cells, shortest_path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "review" / "sim_20261016"
RTL = ["uart_rx.v", "vision_packet_parser.v", "vision_uart_bridge.v",
       "vision_motion_controller.v", "mecanum_kinematics.v", "encoder_speed.v",
       "wheel_pi.v", "motor_pwm_dir.v", "drive_rearm_guard.v", "fpga_robot_core.v",
       "nav/fixed_grid_bfs.v", "nav/acg720_nav_preview.v"]
BENCHES = ["tb_motion_policy", "tb_wheel_control", "tb_four_wheel_pid",
           "tb_drive_rearm_guard", "tb_packet_parser_timeout", "tb_robot_core_pipeline",
           "nav/tb_fixed_grid_bfs", "nav/tb_fixed_grid_bfs_exhaustive",
           "nav/tb_acg720_nav_preview"]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    spec = load_map()
    cells = occupied_cells(spec)
    mem_path = ROOT / "fpga/nav/nav_map_20x20.mem"
    assert cells == [int(v) for v in mem_path.read_text().split()], "JSON 与 .mem 地图漂移"
    rtl = (ROOT / "fpga/nav/fixed_grid_bfs.v").read_text(encoding="utf-8")
    match = re.search(r"MAP_BITS\s*=\s*400'h\s*([0-9a-fA-F]+)", rtl)
    assert match, "缺少显式地图常量"
    bits = int(match[1], 16)
    assert cells == [(bits >> i) & 1 for i in range(400)], "RTL 常量与地图漂移"
    distances = []
    for y in range(20):
        for x in range(20):
            route = shortest_path(spec, cells, (x, y))
            distances.append(len(route) - 1 if route else 511)
    (OUT / "bfs_expected_steps.mem").write_text(
        "".join(f"{v:03x}\n" for v in distances), encoding="ascii")
    shutil.copyfile(mem_path, OUT / mem_path.name)
    # 每项使用独立 WLF；不会争抢用户当前 GUI 已打开的 vsim.wlf。
    commands = ["onerror {quit -code 1 -f}",
                "if {![file isdirectory review_work]} {vlib review_work}",
                "vmap review_work review_work"]
    paths = lambda names, suffix: " ".join(
        "{" + (ROOT / "fpga" / (name + suffix)).as_posix() + "}" for name in names)
    commands.append("vlog -work review_work " + paths(RTL, ""))
    commands.append("vlog -sv -work review_work " + paths(BENCHES, ".sv"))
    for bench in BENCHES:
        name = Path(bench).name
        commands += [f"vsim -wlf {name}.wlf review_work.{name}", "onfinish stop",
                     "run -all", "quit -sim"]
    commands.append("quit -f")
    (OUT / "run.do").write_text("\n".join(commands) + "\n", encoding="utf-8")
    executable = shutil.which("vsim") or shutil.which("vsim.exe")
    if not executable:
        raise RuntimeError("找不到 ModelSim vsim，请先配置 PATH；不下载替代软件")
    process = subprocess.run([executable, "-c", "-l", "modelsim_review.log", "-do", "run.do"],
                             cwd=OUT, capture_output=True, timeout=180)
    # 原始仿真器日志保留编码；摘要只保存 ASCII 的 PASS 和数值，便于不同终端查看。
    (OUT / "console.log").write_bytes(process.stdout + process.stderr)
    text = (process.stdout + process.stderr).decode("gb18030", errors="replace")
    passes = [line.strip("# \r") for line in text.splitlines() if "PASS tb_" in line]
    missing = [Path(b).name for b in BENCHES if not any("PASS " + Path(b).name + ":" in p for p in passes)]
    failure = re.search(r"\*\* (?:Error|Fatal):|\bFAIL\b", text)
    warnings = [line for line in text.splitlines() if "** Warning:" in line]
    summary = {"map_id": spec["map_id"], "cells": len(cells), "occupied": sum(cells),
               "reachable": sum(v != 511 for v in distances), "pass_lines": passes,
               "missing": missing, "warning_count": len(warnings), "exit_code": process.returncode,
               "passed": process.returncode == 0 and not missing and not warnings and failure is None}
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    for line in passes:
        print(line)
    print(json.dumps({k: v for k, v in summary.items() if k != "pass_lines"}, ensure_ascii=False))
    if not summary["passed"]:
        print(text[-7000:])
        raise SystemExit(1)


if __name__ == "__main__":
    main()
