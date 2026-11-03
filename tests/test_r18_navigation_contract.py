"""New navigation scale is explicit; old firmware and smart-task lease persist."""
import struct
import pytest
from src.comm.autonav import counts_per_cell_for_version,pack_autonav_goal,parse_autonav_status
from src.comm.pid_tuning import parse_pid_status,mission_lease_ms
from src.comm.protocol import parse_frame


def test_new_k12_scale_and_no_old_version_change():
    assert parse_pid_status('K12000000040100')['version']==18
    assert counts_per_cell_for_version(18)==500
    assert counts_per_cell_for_version(12)==1000
    assert counts_per_cell_for_version(15)==1000
    assert counts_per_cell_for_version(16)==333
    assert counts_per_cell_for_version(17)==333
    assert mission_lease_ms(18)==mission_lease_ms(17)==600
    assert parse_pid_status('K14000000040100') is None
    with pytest.raises(ValueError):counts_per_cell_for_version(20)


def test_500_count_goal_only_packet_keeps_original_goal():
    frame=parse_frame(pack_autonav_goal(99,(17,2),(17,9),500,-4,True))
    assert frame['msg_type']==0x26
    map_id,sx,sy,gx,gy,counts,setback,flags,speed=struct.unpack('<HBBBBHhBB',frame['payload'])
    assert (map_id,sx,sy,gx,gy,counts,setback,flags,speed)==(0x2613,17,2,17,9,500,-4,1,12)


def test_detour_boundary_failure_is_stopped_not_arrived():
    reply=parse_autonav_status('N0 Q0063 S0C E0E X00 Y03 G00 H09 R01 OFF PFF')
    assert not reply['active'] and reply['state']==12 and reply['reason']==14
    assert (reply['gx'],reply['gy'])==(0,9)
    assert '越界' in reply['reason_name']
