import math
from pathlib import Path
import struct
import sys
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_unified_model import parse_turn_status,btd6_nav_supported
from src.comm.protocol import pack_turn_relative,parse_frame,crc16_ccitt


@pytest.mark.parametrize('angle,inverted',[(15,False),(-90,False),(180,True),(-5,True)])
def test_turn_frame_has_crc_angle_and_mounting_polarity(angle,inverted):
    frame=pack_turn_relative(0x5653,angle,12,inverted)
    parsed=parse_frame(frame)
    assert parsed['msg_type']==0x22 and parsed['seq']==0x5653
    assert struct.unpack('<hBB',parsed['payload'])==(angle*100,12,int(inverted))
    assert len(frame)==14 and crc16_ccitt(frame[2:-2])==int.from_bytes(frame[-2:],'little')


@pytest.mark.parametrize('angle',[0,4.99,181,-181,float('nan'),float('inf'),True])
def test_unsafe_turn_angles_are_rejected(angle):
    with pytest.raises(ValueError):pack_turn_relative(1,angle)


def test_turn_telemetry_decodes_signed_q13_and_remains_separate_from_wheels():
    result=parse_turn_status('Z1 Q1234 S01 CFF00 T3244 E3344')
    assert result['sequence']==0x1234 and result['active']
    assert result['yaw_deg']==pytest.approx(math.degrees(-256/8192))
    assert result['target_deg']==pytest.approx(90,abs=.01)
    assert parse_turn_status('M1 T020 A+000 D0000 F0') is None
    assert parse_turn_status('Z1 Q0001 S01 C00 T00 E00') is None
    assert btd6_nav_supported('SIN10')
