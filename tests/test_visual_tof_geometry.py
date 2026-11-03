from dataclasses import replace
import math
import pytest
from src.core.messages import Detection
from src.detection.visual_tof_geometry import VisualToFCalibration, estimate_target_geometry


def calibration():
    # Synthetic fixture only, not this vehicle's measured calibration.
    return VisualToFCalibration('synthetic-test-only', 640, 480, 500., 500.,
                                320., 240., 200., 3., 0., 0., 0., 150., 5000.)


def bottle(**changes):
    d = Detection(39, 'bottle', .9, 270., 140., 370., 340., 640, 480)
    return replace(d, **changes)


def estimate(d=None, c=None, **changes):
    return estimate_target_geometry(d or bottle(), c or calibration(),
                                   **dict(age_ms=10, confirmed_same_target=True,
                                          full_object_verified=True, **changes))


def test_geometry_offsets_are_depth_dependent_and_never_authorize_motion():
    near = estimate()
    far = estimate(bottle(y1=190., y2=290.))
    assert near['coarse_optical_z_mm'] == 500
    assert far['coarse_optical_z_mm'] == 1000
    assert near['beam_pixel'][0] == 323
    assert far['beam_pixel'][0] == 321.5
    assert near['yaw_left_deg'] == pytest.approx(math.degrees(math.atan(.006)))
    assert near['ray_inside_box']
    assert not near['motion_authorized'] and not near['distance_authoritative']


def test_right_target_needs_right_yaw_and_left_target_left_yaw():
    assert estimate(bottle(x1=350., x2=450.))['yaw_left_deg'] < 0
    assert estimate(bottle(x1=190., x2=290.))['yaw_left_deg'] > 0


@pytest.mark.parametrize('changes', [dict(y1=0), dict(y2=480), dict(x1=0),
                                   dict(x2=640), dict(confidence=.49),
                                   dict(frame_width=320), dict(x1=float('nan'))])
def test_partial_wrong_resolution_or_weak_detection_not_used_for_range(changes):
    assert estimate(bottle(**changes)) is None


@pytest.mark.parametrize('age,confirmed', [(300,True),(-1,True),(float('nan'),True),(0,False)])
def test_stale_or_unconfirmed_has_no_estimate(age, confirmed):
    assert estimate_target_geometry(bottle(),calibration(),age_ms=age,
                                    confirmed_same_target=confirmed,
                                    full_object_verified=True) is None


def test_interior_box_is_not_proof_of_unoccluded_full_height():
    assert estimate_target_geometry(bottle(),calibration(),age_ms=0,
                                    confirmed_same_target=True) is None


def test_missing_or_bad_calibration_fails_closed():
    with pytest.raises(ValueError):
        estimate_target_geometry(bottle(),None,age_ms=0,confirmed_same_target=True)
    for changes in (dict(fx_px=0), dict(calibration_id=''), dict(tof_x_mm=float('inf')),
                    dict(width=True), dict(min_range_mm=6000), dict(tof_yaw_left_deg=90)):
        with pytest.raises(ValueError):
            replace(calibration(), **changes)


def test_range_outside_calibrated_domain_and_beam_miss_are_not_success():
    assert estimate(c=replace(calibration(),min_range_mm=700)) is None
    result = estimate(bottle(x1=450., x2=550.))
    assert not result['ray_inside_box'] and not result['motion_authorized']
