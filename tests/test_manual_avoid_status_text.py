import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_runtime_policy import manual_avoid_status_text
from src.comm.pid_tuning import parse_control_status


def test_reset_disabled_is_not_removed_capability_or_permission():
    status = parse_control_status('O0000000000')
    text = manual_avoid_status_text(status)
    assert not status['avoid_enabled']
    assert '功能可用但未开启' in text and '重配置' in text and '板端确认' in text


def test_fault_and_enabled_are_independent_and_cancellation_explained():
    text = manual_avoid_status_text(parse_control_status('O0001050201'))
    assert '已启用' in text and '原因码2：人工停止/其他控制接管' in text
    assert '受阻保护已停机' in text
    assert '功能可用但未开启' not in text
