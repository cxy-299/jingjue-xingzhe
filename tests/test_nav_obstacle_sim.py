from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))
sys.path.insert(0, str(PROJECT / "fpga" / "motor_bt_drive"))

from pc_unified_model import load_preview_map, preview_goal
from scripts.build_nav_map import add_dynamic_obstacle, shortest_path_from
from src.core.tof_control import ToFDistanceController


def test_tof_hard_stop_then_dynamic_replan():
    spec, cells = load_preview_map()
    goal = (15, 9)
    route = preview_goal(spec, cells, *goal)
    controller = ToFDistanceController(hard_stop_mm=250)
    states = [controller.update(d).state for d in (1200, 900, 600, 400, 280, 220)]
    assert states[-1] == "HARD_STOP"

    current = route[2]
    blocked_next = route[3]
    updated = add_dynamic_obstacle(cells, spec["grid_cells"], blocked_next, radius_cells=0)
    replanned = shortest_path_from(spec, updated, current, goal)
    assert replanned[0] == current
    assert replanned[-1] == goal
    assert blocked_next not in replanned[1:]
