"""The single-window GUI keeps BTD5 locked and gates BTD6 navigation."""

from pathlib import Path
import sys

import pytest


PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "fpga" / "motor_bt_drive"))

from pc_unified_model import (
    btd6_nav_supported,
    parse_sensor_status,
    load_preview_map,
    nav_send_supported,
    pack_btd6_goal,
    pack_btd6_route,
    preview_goal,
    route_directions,
)
from scripts.build_nav_map import add_dynamic_obstacle, shortest_path_from
from src.comm.protocol import MSG_NAV_GOAL, MSG_NAV_PATH, parse_frame


def test_preview_matches_fixed_map_and_obstacle_rejection():
    spec, cells = load_preview_map()
    assert spec["map_id"] == 0x2601
    route = preview_goal(spec, cells, 2, 17)
    assert route[0] == (18, 1)
    assert route[-1] == (2, 17)
    assert len(route) - 1 == 34
    assert preview_goal(spec, cells, 11, 4) == []


@pytest.mark.parametrize("x,y", [(-1, 2), (20, 2), (2, 20), (2.0, 17), (True, 17)])
def test_preview_rejects_invalid_coordinates(x, y):
    spec, cells = load_preview_map()
    with pytest.raises(ValueError):
        preview_goal(spec, cells, x, y)


def test_btd5_navigation_dispatch_is_fail_closed():
    assert nav_send_supported() is False


def test_btd6_goal_is_protocol_compatible_but_explicitly_gated():
    assert btd6_nav_supported("BTD5") is False
    assert btd6_nav_supported("BTD6") is True
    assert btd6_nav_supported("SIN1") is True
    assert btd6_nav_supported("SIN2") is True
    assert btd6_nav_supported("SIN3") is True
    assert btd6_nav_supported("SIN4") is True
    assert btd6_nav_supported("SIN5") is True
    assert btd6_nav_supported("SIN6") is True
    frame = parse_frame(pack_btd6_goal(7, 2, 17))
    assert frame["msg_type"] == MSG_NAV_GOAL
    assert frame["seq"] == 7
    assert frame["payload"] == bytes.fromhex("01 26 02 11")


def test_sensor_status_frames_keep_backward_compatibility_and_wheel_faults():
    legacy = parse_sensor_status("I0 T1 D0111 H0")
    assert legacy[:4] == ("0", "1", "0111", "0")
    assert legacy[4:] == (None,) * 5
    sin3 = parse_sensor_status(
        "I1 T1 D0119 H1 F01 R3F800000 P00000000 Y3E800000")
    assert sin3[4] == "01" and sin3[8] is None
    sin4 = parse_sensor_status(
        "I1 T1 D2908 H0 F10 R3F800000 P00000000 Y3E800000 W5")
    assert sin4[4] == "10" and sin4[8] == "5"
    assert parse_sensor_status("I1 T1 D2908 H0 F10 W5") is None


def test_route_direction_preview_is_not_a_motor_command_stream():
    assert route_directions([(18, 1), (17, 1), (17, 2)]) == "LF"


def test_dynamic_obstacle_replans_from_current_cell():
    spec, cells = load_preview_map()
    original = preview_goal(spec, cells, 15, 9)
    blocked = original[1]
    updated = add_dynamic_obstacle(cells, 20, blocked, radius_cells=0)
    replanned = shortest_path_from(spec, updated, (18, 1), (15, 9))
    assert replanned and replanned[0] == (18, 1) and replanned[-1] == (15, 9)
    assert replanned != original


def test_replan_uses_confirmed_cell_not_fixed_map_origin():
    spec, cells = load_preview_map()
    current = (18, 3)
    goal = (18, 8)
    reroute = shortest_path_from(spec, cells, current, goal)
    assert reroute[0] == current and reroute[-1] == goal
    assert route_directions(reroute) == "FFFFF"
    blocked = add_dynamic_obstacle(cells, 20, (18, 5), radius_cells=1)
    detour = shortest_path_from(spec, blocked, current, goal)
    assert detour[0] == current and detour[-1] == goal
    assert (18, 5) not in detour and len(detour) - 1 == 9


def test_btd6_route_frame_contains_complete_path_codes():
    route = [(18, 1), (17, 1), (17, 2)]
    frame = parse_frame(pack_btd6_route(9, route, 17, 2))
    assert frame["msg_type"] == MSG_NAV_PATH
    assert frame["seq"] == 9
    assert frame["payload"] == bytes.fromhex("01 26 11 02 02 02 00")


def test_zero_step_route_is_not_sent_to_fpga():
    with pytest.raises(ValueError):
        pack_btd6_route(10, [(18, 1)], 18, 1)
