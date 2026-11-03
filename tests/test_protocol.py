from src.comm.protocol import (
    MSG_HEARTBEAT,
    MSG_TARGET,
    MSG_VISION_RESULT,
    crc16_ccitt,
    pack_heartbeat,
    pack_target,
    pack_vision_result,
    parse_frame,
    unpack_vision_result_payload,
)
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentResult

def test_crc_known_vector(): assert crc16_ccitt(b'123456789')==0x29B1

def test_heartbeat_roundtrip():
    p=parse_frame(pack_heartbeat(12,3456)); assert p['msg_type']==MSG_HEARTBEAT and p['seq']==12

def test_target_roundtrip():
    o=TargetObservation(123,True,3,'target',.88,5000,4000,2000,3000); p=parse_frame(pack_target(99,o)); assert p['msg_type']==MSG_TARGET and p['seq']==99


def test_vision_result_roundtrip_for_fpga():
    observation = TargetObservation(
        timestamp_ms=123456,
        valid=True,
        class_id=39,
        class_name='bottle',
        confidence=0.8765,
        cx=6200,
        cy=5100,
        w=2000,
        h=3500,
    )
    alignment = VisualAlignmentResult(
        state='ALIGN_RIGHT',
        vy=0.12,
        omega=0.0,
        center_error=0.24,
        reason='test',
    )

    frame = parse_frame(
        pack_vision_result(7, observation, alignment, frame_id=22)
    )
    assert frame['msg_type'] == MSG_VISION_RESULT
    assert len(frame['payload']) == 26

    result = unpack_vision_result_payload(frame['payload'])
    assert result['valid'] is True
    assert result['confirmed'] is True
    assert result['centered'] is False
    assert result['class_id'] == 39
    assert result['frame_id'] == 22
    assert abs(result['confidence'] - 0.8765) < 0.0001
    assert abs(result['center_error'] - 0.24) < 0.0001
    assert abs(result['area_ratio'] - 0.07) < 0.0001


def test_vision_result_target_lost_is_explicit():
    observation = TargetObservation(timestamp_ms=200, valid=False)
    alignment = VisualAlignmentResult(
        state='SEARCH',
        vy=0.0,
        omega=0.2,
        center_error=0.0,
        reason='lost',
    )
    frame = parse_frame(
        pack_vision_result(8, observation, alignment, frame_id=23)
    )
    result = unpack_vision_result_payload(frame['payload'])
    assert result['valid'] is False
    assert result['confirmed'] is False
    assert result['class_id'] == 0xFFFF
    assert result['alignment'] == 'SEARCH'
