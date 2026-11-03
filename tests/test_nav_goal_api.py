"""只测本地 HTTP 与协议打包；绝不打开串口或启动电机。"""

import json
import threading
import unittest
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from scripts.build_nav_map import load_map, occupied_cells
from src.comm.protocol import MSG_NAV_GOAL, pack_nav_goal, parse_frame
from src.web_gui import DashboardState, make_handler, navigation_settings


ROOT = Path(__file__).resolve().parent.parent


@contextmanager
def local_server(enabled=False, token=""):
    spec = load_map()
    payload = {**spec, "occupied": occupied_cells(spec)}
    state = DashboardState()
    state.status["serial_connected"] = True
    server = ThreadingHTTPServer(
        ("127.0.0.1", 0),
        make_handler(state, ROOT / "web" / "dashboard.html", payload, enabled, token),
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield state, f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def post_goal(url, x, y, token="", map_id=0x2601):
    data = json.dumps({"map_id": map_id, "x": x, "y": y}).encode()
    request = Request(
        url + "/api/nav/goal", data=data,
        headers={"Content-Type": "application/json", "X-Nav-Token": token},
        method="POST",
    )
    try:
        with urlopen(request, timeout=3) as response:
            return response.status, json.load(response)
    except HTTPError as error:
        return error.code, json.load(error)


class NavGoalTests(unittest.TestCase):
    def test_protocol_payload_and_crc(self):
        frame = parse_frame(pack_nav_goal(7, 2, 17))
        self.assertEqual(frame["msg_type"], MSG_NAV_GOAL)
        self.assertEqual(frame["payload"], bytes([0x01, 0x26, 2, 17]))
        with self.assertRaises(ValueError):
            pack_nav_goal(7, 20, 0)

    def test_default_locked_and_map_matches_memory(self):
        with local_server() as (state, base):
            with urlopen(base + "/api/nav/map", timeout=3) as response:
                page = json.load(response)
            mem = (ROOT / "fpga" / "nav" / "nav_map_20x20.mem").read_text().split()
            self.assertEqual(page["occupied"], [int(bit) for bit in mem])
            status, _ = post_goal(base, 2, 17)
            self.assertEqual(status, 423)
            self.assertIsNone(state.take_nav_goal())

    def test_token_map_and_blocked_goal(self):
        with local_server(enabled=True, token="test-only") as (state, base):
            self.assertEqual(post_goal(base, 2, 17)[0], 403)
            self.assertEqual(post_goal(base, 2, 17, "test-only", map_id=1)[0], 400)
            self.assertEqual(post_goal(base, 11, 4, "test-only")[0], 400)
            self.assertEqual(post_goal(base, 2, 17, "test-only")[0], 202)
            # 前一条目标未发出时，第二条必须被拒绝，不能悄悄覆盖。
            self.assertEqual(post_goal(base, 1, 17, "test-only")[0], 409)
            self.assertEqual(state.take_nav_goal(), (2, 17))
            self.assertEqual(post_goal(base, 1, 17, "test-only")[0], 409)
            state.nav_sent(2, 17, True)
            self.assertEqual(post_goal(base, 1, 17, "test-only")[0], 202)

    def test_pi_page_has_instance_lock_instead_of_map(self):
        with local_server() as (_state, base):
            with urlopen(base, timeout=3) as response:
                html = response.read().decode("utf-8")
            self.assertNotIn('id="navMap"', html)
            self.assertIn('id="taskLockButton"', html)
            self.assertIn('id="taskFollow"', html)

    def test_expired_goal_is_not_sent_after_camera_recovers(self):
        now = [100.0]
        state = DashboardState(goal_ttl_s=2.0, clock=lambda: now[0])
        self.assertTrue(state.queue_nav_goal(3, 12))
        now[0] += 2.0
        snapshot = state.status_snapshot()
        self.assertFalse(snapshot["nav_goal_pending"])
        self.assertIn("超时", snapshot["nav_goal_state"])
        self.assertIsNone(state.take_nav_goal())
        # 过期目标不会占住单槽，新目标仍可发送并单独保存协议序号。
        self.assertTrue(state.queue_nav_goal(2, 17))
        self.assertEqual(state.take_nav_goal(), (2, 17))
        state.nav_sent(2, 17, True, sequence=65535)
        self.assertEqual(state.status_snapshot()["nav_goal_last_seq"], 65535)

    def test_expiry_checked_without_polling_and_does_not_replace_in_flight(self):
        now = [0.0]
        state = DashboardState(clock=lambda: now[0])
        state.queue_nav_goal(3, 12)
        now[0] = 3.0
        self.assertIsNone(state.take_nav_goal())
        state.queue_nav_goal(2, 17)
        self.assertEqual(state.take_nav_goal(), (2, 17))
        now[0] = 10.0
        self.assertFalse(state.queue_nav_goal(3, 12))
        state.nav_sent(2, 17, False)
        self.assertIsNone(state.status_snapshot()["nav_goal_last_sent"])

    def test_invalid_navigation_config_is_locked(self):
        # 复现实机曾出现的 YAML 解析为字符串，以及字符串 false 被 bool 误判为真。
        for nav in ("goal_tx_enabled:true control_token:test", [],
                    {"goal_tx_enabled": "false"}, {"control_token": 123},
                    {"goal_tx_enabled": True, "control_token": "  "}):
            enabled, token, error = navigation_settings({"navigation": nav})
            self.assertFalse(enabled)
            self.assertEqual(token, "")
            self.assertIn("已锁定", error)
        self.assertEqual(navigation_settings({}), (False, "", ""))
        self.assertEqual(navigation_settings({"navigation": {
            "goal_tx_enabled": True, "control_token": "test-only"
        }}), (True, "test-only", ""))

    def test_grid_fields_must_be_json_integers(self):
        with local_server(enabled=True, token="test-only") as (_state, base):
            self.assertEqual(post_goal(base, 3.0, 12, "test-only")[0], 400)
            self.assertEqual(post_goal(base, True, 12, "test-only")[0], 400)
            self.assertEqual(post_goal(base, 3, 12, "test-only", map_id=9729.0)[0], 400)


if __name__ == "__main__":
    unittest.main()
