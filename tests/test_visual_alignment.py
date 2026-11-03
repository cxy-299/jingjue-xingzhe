from src.core.visual_alignment import VisualAlignmentController
from src.core.messages import TargetObservation


def obs(cx=5000, valid=True):
    return TargetObservation(
        timestamp_ms=1,
        valid=valid,
        class_id=0,
        class_name='person',
        confidence=.9,
        cx=cx, cy=5000, w=2000, h=3000
    )


def test_visual_left_right_center():
    c = VisualAlignmentController(target_confirm_frames=1, smoothing_alpha=1.0)
    left = c.update(obs(2500))
    assert left.state == 'ALIGN_LEFT'
    assert left.vy < 0

    right = c.update(obs(7500))
    assert right.state == 'ALIGN_RIGHT'
    assert right.vy > 0

    center = c.update(obs(5000))
    assert center.state == 'CENTERED'
    assert center.vy == 0
