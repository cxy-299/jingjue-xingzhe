from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_runtime_policy import confirmed_digit_follow_trigger


@pytest.mark.parametrize('digit',range(10))
def test_current_confirmed_digit_metadata_only(digit):
    result=confirmed_digit_follow_trigger(dict(class_id=0xA400+digit,lock_id=42,fresh=True,visible=True),10.,10.2)
    assert result==dict(digit=digit,class_id=0xA400+digit,lock_id=42)


@pytest.mark.parametrize('change,age',[(dict(visible=False),.1),(dict(fresh=False),.1),
    (dict(class_id=39),.1),(dict(class_id=0xA40A),.1),(dict(lock_id=0),.1),
    (dict(lock_id=True),.1),({},2.),({},-.1)])
def test_missing_unknown_or_stale_never_triggers(change,age):
    vision=dict(class_id=0xA406,lock_id=42,fresh=True,visible=True);vision.update(change)
    assert confirmed_digit_follow_trigger(vision,10.,10.+age) is None
