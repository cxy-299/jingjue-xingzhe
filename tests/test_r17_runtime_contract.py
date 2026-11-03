from src.comm.pid_tuning import parse_pid_status,mission_lease_ms
from src.comm.autonav import counts_per_cell_for_version

def test_explicit_r17_backward_compatible_host_contract():
    assert parse_pid_status('K11000000040100')['version']==17
    assert mission_lease_ms(17)==600
    assert counts_per_cell_for_version(17)==333
    assert counts_per_cell_for_version(16)==333
    assert counts_per_cell_for_version(15)==1000
    assert parse_pid_status('K13000000040100') is None
