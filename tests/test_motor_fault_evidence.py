import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive'))
from pc_unified_model import parse_motor_fault_snapshot


@pytest.mark.parametrize('code,speed,label', [(1, 0, '连续无反馈'), (2, -3, '连续反向反馈'), (4, 51, '超速计数'), (3, -5, '连续无反馈、连续反向反馈')])
def test_first_fault_snapshot_not_current_stopped_speed(code, speed, label):
    value = parse_motor_fault_snapshot(f'M3 T008 A+000 D0000 F1 E{code} X{speed:+04d} P0800')
    assert value == dict(wheel=3, reason=code, reason_text=label, speed=speed, duty=800)


@pytest.mark.parametrize('line', [
    'M3 T008 A+000 D0000 F1',
    'M3 T008 A+000 D0000 F0 E1 X+000 P0800',
    'M3 T008 A+000 D0000 F1 E1 X+000 P1001',
    'M3 T008 A+000 D0000 F1 E0 X+000 P0800',
    'M5 T008 A+000 D0000 F1 E1 X+000 P0800',
])
def test_legacy_or_malformed_has_no_diagnostic_claim(line):
    assert parse_motor_fault_snapshot(line) is None
