import pytest
from src.comm.mission_readiness import check_mission_readiness


def status(**changes):
    return dict(online=True, task_mode='mission', mission_id=1,
                mission_perception_tx_id=1, mission_perception_tx_age_ms=100,
                mission_class='bottle', **changes)


def test_confirmed_selected_instance_can_start_despite_other_bottles():
    assert '接近' in check_mission_readiness(status(task_lock_id=9,
        task_target_locked=True, task_target_confirmed=True, mission_candidate_count=2))


def test_ambiguous_unselected_targets_cannot_start_even_with_search_enabled():
    with pytest.raises(ValueError, match='2个候选'):
        check_mission_readiness(status(mission_candidate_count=2), allow_search=True)


def test_fixed_chassis_default_cannot_start_unlocked_scan():
    with pytest.raises(ValueError, match='底盘实际可转动'):
        check_mission_readiness(status(mission_candidate_count=0))
    assert '真实转动' in check_mission_readiness(status(mission_candidate_count=0), True)


def test_lost_lock_cannot_fall_back_to_scan_or_reacquire_arbitrary_object():
    with pytest.raises(ValueError, match='暂不可见'):
        check_mission_readiness(status(task_lock_id=9, mission_candidate_count=0), True)


def test_stale_usb_perception_is_rejected_even_with_confirmed_target():
    data=status(task_lock_id=9, task_target_locked=True, task_target_confirmed=True)
    data['mission_perception_tx_age_ms']=1300
    with pytest.raises(ValueError, match='新鲜USB'):
        check_mission_readiness(data)


def test_previous_pi_version_counts_visible_candidates_conservatively():
    data=status(detections=[dict(class_name='bottle',confidence=.9),
                            dict(class_name='person',confidence=.9)])
    with pytest.raises(ValueError, match='连续确认'):
        check_mission_readiness(data, True)
