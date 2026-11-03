from src.comm.autonav import counts_per_cell_for_version,pack_autonav_goal,parse_autonav_status
from src.comm.pid_tuning import parse_pid_status,mission_lease_ms
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_runtime_policy import navigation_obstacle_point

def test_r20_identity_and_scale():
 assert parse_pid_status('K14000000040100')['version']==20
 assert counts_per_cell_for_version(20)==500
 assert mission_lease_ms(20)==600
 assert counts_per_cell_for_version(19)==500
 assert counts_per_cell_for_version(17)==333

def test_r20_projection_is_reported_cell_not_manual_fixture():
 s=parse_autonav_status('N1 Q1234 S04 E00 X11 Y02 G11 H11 R01 O11 P0C')
 request={'version':20,'sequence':0x1234,'goal':(17,17)}
 assert navigation_obstacle_point(s,request,version=20,capability_fresh=True)==(17,12)
 assert navigation_obstacle_point(s,request,version=20,capability_fresh=False) is None
 assert navigation_obstacle_point(s,{**request,'sequence':0x1235},version=20,capability_fresh=True) is None

def test_r20_invalid_projection_not_replaced_by_manual_cell():
 s=parse_autonav_status('N1 Q1234 S04 E00 X11 Y02 G11 H11 R01 OFF PFF')
 assert navigation_obstacle_point(s,{'version':20,'sequence':0x1234,'goal':(17,17)},version=20,capability_fresh=True) is None
