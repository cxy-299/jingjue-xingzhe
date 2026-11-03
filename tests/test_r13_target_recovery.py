from src.comm.mission import parse_mission_status
from src.comm.pid_tuning import parse_pid_status


def test_r13_pause_is_active_distinct_from_failure_and_success():
    paused = parse_mission_status('J1 Q8C3D63C2 S10 C0027 K00000003 N0')
    assert paused['active'] and paused['state'] == 16
    assert paused['task_id'] == 0x8C3D63C2 and paused['lock_id'] == 3
    assert '停车等待' in paused['state_name']
    for state in ('06', '08', '09', '0A', '0C', '0E'):
        ended = parse_mission_status(f'J0 Q8C3D63C2 S{state} C0027 K00000003 N0')
        assert not ended['active'] and ended['state'] != paused['state']


def test_r13_capability_explicit_and_backward_compatible():
    for version in range(4, 16):
        assert parse_pid_status(f'K{version:02X}000000040100')['version'] == version
    assert parse_pid_status('K0F000000040100')['version']==15
    assert parse_pid_status('K10000000040100') is None
