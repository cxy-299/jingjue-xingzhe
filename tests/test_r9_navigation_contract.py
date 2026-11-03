import sys
from pathlib import Path
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_runtime_policy import map_navigation_reply
from src.comm.pid_tuning import parse_pid_status

REQUEST=dict(sequence=123,start=(17,2),goal=(17,9))

@pytest.mark.parametrize('changes,result',[
    ({},'arrived'), ({'active':True,'state':7,'y':3},'active'),
    ({'sequence':124},'unrelated'), ({'local_mode':True},'mode_mismatch'),
    ({'gy':3},'goal_mismatch'), ({'gx':3},'goal_mismatch'),
    ({'y':3},'invalid_completion'), ({'reason':10,'state':12,'y':3},'stopped'),
    ({'state':8,'y':3},'stopped'), ({'reason':13,'state':12},'stopped')])
def test_only_matching_submitted_map_goal_can_complete(changes,result):
    status=dict(sequence=123,local_mode=False,active=False,state=11,reason=0,x=17,y=9,gx=17,gy=9)
    status.update(changes)
    assert map_navigation_reply(status,REQUEST)==result
    assert REQUEST['goal']==(17,9)

def test_k09_is_explicit_capability_and_unknown_version_rejected():
    assert parse_pid_status('K09000000040100')['version']==9
    assert parse_pid_status('K0F000000040100')['version']==15
    assert parse_pid_status('K10000000040100')['version']==16
    assert parse_pid_status('K11000000040100')['version']==17
    assert parse_pid_status('K13000000040100') is None
