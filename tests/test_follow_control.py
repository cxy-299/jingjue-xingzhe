from src.core.follow_control import FollowController


def valid(c, distance, center=0.0, yaw=0.0):
    return c.update(
        target_valid=True,
        center_error=center,
        distance_mm=distance,
        tof_valid=True,
        imu_valid=True,
        yaw_deg=yaw,
    )


def test_follow_approaches_and_holds_300mm():
    c = FollowController(smoothing_alpha=1.0)
    c.lock(0.0)
    assert valid(c, 600).vx > 0
    held = valid(c, 300)
    assert held.state == "HOLD_300MM"
    assert held.vx == 0


def test_distance_deadband_stops_without_iir_coasting_tail():
    c = FollowController(target_mm=200, hard_stop_mm=100, smoothing_alpha=0.35)
    c.lock(0.0)
    for _ in range(15):assert valid(c,600).vx>0
    assert valid(c,210).vx==0
    for _ in range(15):assert valid(c,140).vx<0
    assert valid(c,190).vx==0


def test_follow_reverses_when_too_close_but_hard_stops_near_collision():
    c = FollowController(smoothing_alpha=1.0)
    c.lock(0.0)
    assert valid(c, 270).vx < 0
    assert valid(c, 210).state == "HARD_STOP"


def test_follow_uses_visual_center_and_imu_heading():
    c = FollowController(smoothing_alpha=1.0)
    c.lock(10.0)
    result = valid(c, 300, center=0.5, yaw=20.0)
    assert result.vy > 0
    assert result.omega < 0


def test_follow_fails_safe_on_missing_sensor_or_target():
    c = FollowController()
    c.lock(0.0)
    assert c.update(target_valid=False, tof_valid=True, imu_valid=True).state == "TARGET_LOST"
    assert c.update(target_valid=True, tof_valid=False, imu_valid=True).state == "TOF_FAULT"
    assert c.update(target_valid=True, tof_valid=True, imu_valid=False).state == "IMU_FAULT"
