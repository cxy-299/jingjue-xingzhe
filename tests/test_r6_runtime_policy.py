from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_runtime_policy import can_acknowledge_block, continue_local_forward
from src.comm.pid_tuning import parse_pid_status, parse_control_status

def test_r6_capability_and_resume_state():
    assert parse_pid_status('K06000000040100')['version']==6
    assert parse_pid_status('K07000000040100')['version']==7
    assert parse_pid_status('K08000000040100')['version']==8
    assert parse_pid_status('K0D000000040100')['version']==13
    assert parse_pid_status('K0E000000040100')['version']==14
    assert parse_pid_status('K0F000000040100')['version']==15
    assert parse_pid_status('K10000000040100') is None
    assert parse_control_status('O0001060000')['state']==6
    assert parse_control_status('O0001070000') is None

@pytest.mark.parametrize('change',[{}, {'version':5},{'capability_fresh':False},{'held':None},
    {'mode':'turn'},{'permitted':False}])
def test_continuation_needs_new_capability_and_operator_intent(change):
    previous=dict(local_mode=True,active=True,sequence=30)
    current=dict(local_mode=True,active=False,sequence=30,state=11,reason=0)
    opts=dict(version=6,capability_fresh=True,held='F',mode='manual',permitted=True)
    opts.update(change)
    assert bool(continue_local_forward(previous,current,**opts)) == (not change)
    for key,value in [('state',12),('reason',5),('sequence',29),('local_mode',False)]:
        assert not continue_local_forward(previous,{**current,key:value},**opts)

@pytest.mark.parametrize('change',[{}, {'attempted':True},{'pending':True},{'fault_bits':0},
    {'blocked':0},{'severe':2},{'fresh':False},{'command':1},{'speeds':[0,2,0,0]},
    {'speeds':[]},{'idle':False},{'sensors_clear':False},{'evidence':{}},
    {'evidence':{2:4}},{'version':4}])
def test_block_ack_does_not_bypass_fault_or_motion(change):
    opts=dict(version=6,attempted=False,pending=False,fault_bits=16,blocked=2,severe=0,
              fresh=True,command=0,speeds=[0]*4,idle=True,sensors_clear=True,evidence={2:1})
    opts.update(change)
    assert can_acknowledge_block(**opts)==(not change)
