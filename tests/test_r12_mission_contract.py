from src.comm.pid_tuning import parse_pid_status
from src.comm.mission import parse_mission_status


def test_r12_explicit_capability_keeps_old_versions_and_rejects_unknown():
    assert parse_pid_status('K0C000000040100')['version'] == 12
    assert parse_pid_status('K0B000000040100')['version'] == 11
    assert parse_pid_status('K0D000000040100')['version'] == 13
    assert parse_pid_status('K0E000000040100')['version'] == 14
    assert parse_pid_status('K0F000000040100')['version']==15
    assert parse_pid_status('K10000000040100') is None


def test_board_lease_expiry_and_host_cancellation_are_distinct():
    expired = parse_mission_status('J0 QE8EA8667 S08 C0027 K00000006 N0')
    cancelled = parse_mission_status('J0 QE8EA8667 S0C C0027 K00000006 N0')
    assert expired['state_name'] == '运动许可超时'
    assert cancelled['state_name'] == '任务取消'
    assert not expired['active'] and not cancelled['active']
