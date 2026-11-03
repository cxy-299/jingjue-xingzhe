from src.core.tof_control import ToFDistanceController


def test_tof_far_approach_and_stop():
    c = ToFDistanceController(
        target_mm=500,
        deadband_mm=50,
        hard_stop_mm=250,
        smoothing_alpha=1.0,
    )

    far = c.update(1500, True)
    assert far.state == 'APPROACH'
    assert far.vx > 0

    ok = c.update(520, True)
    assert ok.state == 'DISTANCE_OK'
    assert ok.vx == 0

    hard = c.update(200, True)
    assert hard.state == 'HARD_STOP'
    assert hard.vx == 0

    fault = c.update(1500, False)
    assert fault.state == 'TOF_FAULT'
    assert fault.vx == 0
