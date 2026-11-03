from src.comm.pid_tuning import parse_pid_status
from src.comm.mission import parse_mission_status


def test_r11_capability_is_explicit_and_next_version_rejected():
    assert parse_pid_status('K0B000000040100')['version'] == 11
    assert parse_pid_status('K0A000000040100')['version'] == 10
    assert parse_pid_status('K0F000000040100')['version']==15
    assert parse_pid_status('K10000000040100') is None


def test_lateral_guard_does_not_report_completion_or_motor_damage():
    state = parse_mission_status('J0 Q938DB6A1 S0F C0027 K0000000E N0')
    assert state['state'] == 15 and not state['active']
    assert '偏航' in state['state_name']
    assert '完成' not in state['state_name'] and '电机' not in state['state_name']
