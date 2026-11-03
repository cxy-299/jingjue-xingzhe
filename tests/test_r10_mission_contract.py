from src.comm.pid_tuning import parse_pid_status
from src.comm.mission import parse_mission_status

def test_explicit_r10_capability_and_mission_heading_stop():
    assert parse_pid_status('K0A000000040100')['version']==10
    assert parse_pid_status('K0F000000040100')['version']==15
    assert parse_pid_status('K10000000040100') is None
    status=parse_mission_status('J0 Q8FC31442 S0F C0027 K00000006 N0')
    assert status['state']==15 and not status['active']
    assert '偏航超过8°' in status['state_name']
