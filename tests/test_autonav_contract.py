from pathlib import Path
import json
import pytest
from src.comm.autonav import pack_autonav_goal, parse_autonav_status
from src.comm.protocol import parse_frame
from scripts.build_nav_map import occupied_cells, shortest_path_from


def test_goal_only_frame_and_signed_mount_offset():
    frame=pack_autonav_goal(7,(17,2),(10,17),1000,-10,True,False,12)
    assert len(frame)==22
    p=parse_frame(frame)
    assert p['msg_type']==0x26 and p['payload'][:6]==bytes.fromhex('13 26 11 02 0a 11')
    assert p['payload'][8:]==bytes.fromhex('f6 ff 01 0c')


@pytest.mark.parametrize('field,value',[
    ('geometry_confirmed',False),('tof_setback_mm',None),('tof_setback_mm',True),
    ('tof_setback_mm',51),('speed',20),('counts_per_cell',0),('goal',(20,1)),
    ('start',(True,1)),('goal',(1,)),('start',(1,2,3)),
])
def test_rejects_unknown_geometry_or_invalid_request(field,value):
    args=dict(sequence=1,start=(17,2),goal=(17,3),counts_per_cell=1000,
              tof_setback_mm=0,geometry_confirmed=True,speed=12)
    args[field]=value
    with pytest.raises((ValueError,TypeError)):pack_autonav_goal(**args)


def test_actual_navigation_telemetry():
    p=parse_autonav_status('N1 Q0031 S07 E00 X11 Y02 G0A H11 R01 O0C P04')
    assert p['active'] and p['sequence']==49 and p['obstacle']==(12,4)
    assert p['state_name']=='前进' and p['replans']==1
    assert parse_autonav_status('COM9 已打开 TX正常') is None
    assert not parse_autonav_status('N0 Q0031 S0B E00 X0A Y11 G0A H11 R01 OFF PFF')['active']


def test_reobserve_is_active_stopped_evidence_not_arrival_or_motor_fault():
    p=parse_autonav_status('N1 Q20BA S0E E00 X11 Y02 G11 H09 R01 OFF PFF')
    assert p['active'] and p['state']==14 and p['reason']==0
    assert p['state_name']=='遇障停稳·重新确认测距与位姿'
    assert p['obstacle']==(255,255) and (p['gx'],p['gy'])==(17,9)


def test_field_phantom_coordinate_is_board_reply_not_gui_axis_flip():
    p=parse_autonav_status('N1 Q20BA S04 E00 X11 Y05 G11 H07 R01 O11 P0A')
    assert (p['x'],p['y'])==(17,5) and p['obstacle']==(17,10)
    assert (p['gx'],p['gy'])==(17,7)  # recorded job, not operator example


def test_independent_map_matches_rtl_and_preserves_original():
    root=Path(__file__).resolve().parents[1]
    spec=json.loads((root/'config/nav-map-sin12.json').read_text(encoding='utf-8'))
    cells=occupied_cells(spec)
    expected=sum(value<<i for i,value in enumerate(cells))
    vh=(root/'fpga/nav/sin12_map.vh').read_text()
    assert f"400'h{expected:0100X}" in vh
    assert spec['robot_width_m']==.22 and spec['robot_length_m']==.2
    assert spec['map_id']==0x2613 and "SIN12_MAP_ID 16'h2613" in vh
    assert spec['inflation_radius_m']==.21
    assert len(spec['obstacles'])==4
    reachable=sum(bool(shortest_path_from(spec,cells,(17,2),(x,y))) for y in range(20) for x in range(20))
    assert reachable >= 160
    assert len(shortest_path_from(spec,cells,(17,2),(10,17)))-1==22
    old=json.loads((root/'config/nav-map-2m.json').read_text(encoding='utf-8'))
    assert old['map_id']==0x2601 and old['start_cell']==[18,1]
