"""Map points use stopped board coordinates, never the live robot/range."""
import sys
from pathlib import Path
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_runtime_policy import navigation_obstacle_point
from src.comm.autonav import counts_per_cell_for_version
from src.comm.pid_tuning import parse_pid_status,mission_lease_ms

def test_r19_scale_and_identity():
    assert parse_pid_status('K13000000040100')['version']==19
    assert parse_pid_status('K15000000040100') is None
    assert counts_per_cell_for_version(19)==500
    assert [counts_per_cell_for_version(v) for v in (12,16,17,18)]==[1000,333,333,500]
    assert mission_lease_ms(19)==600
    with pytest.raises(ValueError):counts_per_cell_for_version(21)

def status(**kw):
    return dict(sequence=3,gx=17,gy=11,local_mode=False,state=15,active=True,
                reason=0,replans=1,x=17,y=4,obstacle=(17,7),**kw)

def request():return dict(sequence=3,goal=(17,11),version=19)

def test_stopped_point_is_not_robot_cell_or_goal():
    assert navigation_obstacle_point(status(),request(),version=19,capability_fresh=True)==(17,7)

@pytest.mark.parametrize('field,value',[
    ('sequence',2),('gx',16),('local_mode',True),('state',0),('state',8),('state',13),('state',14),
    ('replans',0),('obstacle',(255,255)),('obstacle',(17,20)),('obstacle',(-1,5))])
def test_unrelated_pending_invalid_points_ignored(field,value):
    s=status();s[field]=value
    assert navigation_obstacle_point(s,request(),version=19,capability_fresh=True) is None

@pytest.mark.parametrize('version,fresh',[(12,True),(18,True),(20,True),(19,False)])
def test_no_fake_new_measurement_for_legacy_or_stale_version(version,fresh):
    assert navigation_obstacle_point(status(),request(),version=version,capability_fresh=fresh) is None
