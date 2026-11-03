"""Pure-software acceptance chain for competition tasks 1--4.

This deliberately stops before GPIO/PWM: it proves that valid sensor data,
the safety policy, map replanning and the FPGA path protocol agree on one
coordinate/control contract while the board is powered off.
"""

from scripts.build_nav_map import add_dynamic_obstacle, load_map, occupied_cells, shortest_path_from
from src.comm.protocol import MSG_NAV_PATH, parse_frame
from src.sensors.atk_ms53l2m import MultiToFSafetyGuard
from src.sensors.yahboom_imu import YahboomImuParser, build_frame
from fpga.motor_bt_drive.pc_unified_model import pack_btd6_route, route_directions


def test_tasks_1_to_4_sensor_safety_replan_and_fpga_frame_chain():
    imu = YahboomImuParser()
    angle = imu.feed(build_frame(0x53, (0, 0, 8192, 0)))[0]
    assert angle.kind == "angle" and angle.yaw_deg == 45.0

    guard = MultiToFSafetyGuard()
    assert guard.update([800]).state == "CLEAR"
    assert guard.update([400]).state == "DECEL"
    assert guard.update([200]).state == "HARD_STOP"

    spec = load_map()
    cells = occupied_cells(spec)
    start, goal = tuple(spec["start_cell"]), (15, 9)
    route = shortest_path_from(spec, cells, start, goal)
    updated = add_dynamic_obstacle(cells, 20, route[1], radius_cells=0)
    reroute = shortest_path_from(spec, updated, start, goal)
    assert reroute and reroute != route

    frame = parse_frame(pack_btd6_route(12, reroute, *goal))
    assert frame["msg_type"] == MSG_NAV_PATH
    assert route_directions(reroute)
