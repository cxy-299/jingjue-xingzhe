from src.core.messages import TargetObservation
from src.core.decision import DecisionSimulator


def obs(valid=True, cx=5000, cy=5000, w=1000, h=1000):
    return TargetObservation(
        timestamp_ms=0,
        valid=valid,
        class_id=0,
        class_name='person',
        confidence=.9,
        cx=cx, cy=cy, w=w, h=h,
    )


def get_stable(sim, o, n=4):
    r = None
    for _ in range(n):
        r = sim.update(o)
    return r


def test_search_after_loss_confirmation():
    sim = DecisionSimulator(target_confirm_frames=1, lost_confirm_frames=2)
    assert sim.update(obs(valid=False)).action == 'HOLD'
    assert sim.update(obs(valid=False)).action == 'SEARCH'


def test_far_center_approaches():
    sim = DecisionSimulator(target_confirm_frames=1, smoothing_alpha=1.0)
    r = sim.update(obs(cx=5000, w=1800, h=2500))
    assert r.action == 'APPROACH'
    assert r.vx > 0
    assert r.vy == 0


def test_far_left_approaches_and_aligns_simultaneously():
    sim = DecisionSimulator(target_confirm_frames=1, smoothing_alpha=1.0)
    r = sim.update(obs(cx=2500, w=1800, h=2500))
    assert r.action == 'APPROACH_LEFT'
    assert r.vx > 0
    assert r.vy < 0


def test_far_right_approaches_and_aligns_simultaneously():
    sim = DecisionSimulator(target_confirm_frames=1, smoothing_alpha=1.0)
    r = sim.update(obs(cx=7500, w=1800, h=2500))
    assert r.action == 'APPROACH_RIGHT'
    assert r.vx > 0
    assert r.vy > 0


def test_close_center_stops_immediately():
    sim = DecisionSimulator(target_confirm_frames=1, smoothing_alpha=1.0, stop_area_ratio=.12)
    r = sim.update(obs(cx=5000, w=4000, h=4000))
    assert r.action == 'STOP'
    assert r.vx == 0


def test_close_left_only_aligns_without_forward_motion():
    sim = DecisionSimulator(target_confirm_frames=1, smoothing_alpha=1.0, stop_area_ratio=.12)
    r = sim.update(obs(cx=3000, w=4000, h=4000))
    assert r.action == 'ALIGN_LEFT'
    assert r.vx == 0
    assert r.vy < 0


def test_hysteresis_prevents_chatter():
    sim = DecisionSimulator(
        target_confirm_frames=1,
        smoothing_alpha=1.0,
        stop_area_ratio=.12,
        resume_area_ratio=.10,
    )
    assert sim.update(obs(w=4000, h=3000)).action == 'STOP'  # area=.12
    r = sim.update(obs(w=3700, h=3000))  # area=.111 -> still latched near
    assert r.action == 'STOP'
    r = sim.update(obs(w=3000, h=3000))  # area=.09 -> resume
    assert r.action == 'APPROACH'
    assert r.vx > 0
