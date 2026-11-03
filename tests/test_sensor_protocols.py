from src.sensors.atk_ms53l2m import ATKMS53L2MParser, MultiToFSafetyGuard
from src.sensors.yahboom_imu import YahboomImuParser, build_frame


def test_yahboom_angle_frame_and_resync():
    parser = YahboomImuParser()
    valid = build_frame(0x53, (8192, -4096, 16384, 0))
    bad = bytearray(valid)
    bad[-1] ^= 0x01
    frames = parser.feed(b"noise" + bytes(bad) + valid[:4])
    assert frames == []
    frames = parser.feed(valid[4:])
    assert len(frames) == 1
    assert frames[0].kind == "angle"
    assert round(frames[0].roll_deg, 3) == 45.0
    assert round(frames[0].pitch_deg, 3) == -22.5
    assert round(frames[0].yaw_deg, 3) == 90.0
    assert parser.frames_bad >= 1


def test_tof_parser_accepts_normal_and_strength_lines():
    parser = ATKMS53L2MParser()
    readings = parser.feed(b"1200\r\n450,987\r\n\n")
    assert [r.distance_mm for r in readings] == [1200, 450]
    assert parser.feed(b"20\r\n9000\r\n") == []
    assert parser.invalid_lines == 2


def test_tof_safety_policy():
    guard = MultiToFSafetyGuard()
    assert guard.update([None, None, None, None]).state == "TOF_FAULT"
    assert guard.update([1000, None, 900, None]).speed_scale_permille == 1000
    assert guard.update([450, 1200, None, None]).state == "DECEL"
    assert guard.update([200, 1200, None, None]).state == "HARD_STOP"
