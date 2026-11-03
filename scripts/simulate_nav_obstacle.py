"""离线复现：车辆沿规划路径行驶时遇到 ToF 障碍，安全停车并重规划。

该脚本不连接串口、不驱动电机，只验证三条逻辑链：
1. ToF 距离从远到近时由接近状态进入减速和硬停止；
2. 硬停止位置加入动态障碍；
3. 从当前位置对原目标重新做 BFS，且新路径不再经过障碍格。
"""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.build_nav_map import add_dynamic_obstacle, shortest_path_from
from src.core.tof_control import ToFDistanceController
from fpga.motor_bt_drive.pc_unified_model import load_preview_map, preview_goal


def main() -> None:
    spec, cells = load_preview_map()
    start = tuple(spec["start_cell"])
    goal = (15, 9)
    route = preview_goal(spec, cells, *goal)
    if len(route) < 5:
        raise RuntimeError("示例路径过短，无法演示行驶中障碍")

    tof = ToFDistanceController(hard_stop_mm=250)
    print(f"START={start} GOAL={goal} STEPS={len(route) - 1}")
    for distance in (1200, 900, 600, 400, 280, 220):
        result = tof.update(distance)
        print(f"TOF {distance:4d} mm -> {result.state:10s} vx={result.vx:.3f}")
    assert result.state == "HARD_STOP" and result.vx == 0.0

    current_index = 2
    current = route[current_index]
    obstacle = route[current_index + 1]
    updated = add_dynamic_obstacle(cells, spec["grid_cells"], obstacle, radius_cells=0)
    replanned = shortest_path_from(spec, updated, current, goal)
    if not replanned or replanned[0] != current or replanned[-1] != goal:
        raise RuntimeError("动态障碍加入后没有得到有效替代路径")
    assert obstacle not in replanned[1:]
    print(f"HARD_STOP_AT={current} BLOCKED_NEXT={obstacle}")
    print(f"REPLAN_STEPS={len(replanned) - 1}")
    print("PASS nav obstacle stop + replan")


if __name__ == "__main__":
    main()
