import pytest
from src.comm.pid_tuning import parse_control_status, parse_pid_status
from src.comm.autonav import parse_autonav_status


def test_r5_capability_sequence_and_masks():
    assert parse_pid_status('K05000000040100')['version'] == 5
    s = parse_control_status('OFF09000002')
    assert s['sequence'] == 255 and s['avoid_enabled'] and s['recovery_result'] == 2
    assert s['blocked_mask'] == 2 and s['severe_mask'] == 0
    for bad in ('O09000002','O0010000000','O000C000000','O0000070000','O0000000900','O0000000022'):
        assert parse_control_status(bad) is None


def test_local_navigation_is_explicitly_distinct_from_field_coordinates():
    s = parse_autonav_status('N1 QFFFF S87 E00 X0A Y05 G0A H0F R01 OFF PFF')
    assert s['local_mode'] and s['state'] == 7 and s['state_name'] == '前进'
    s = parse_autonav_status('N1 Q0000 S07 E00 X0A Y05 G0A H0F R01 OFF PFF')
    assert not s['local_mode'] and s['state'] == 7
