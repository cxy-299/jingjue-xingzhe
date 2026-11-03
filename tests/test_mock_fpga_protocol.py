from src.comm.protocol import (
    MSG_VISUAL_ALIGNMENT,
    pack_visual_alignment,
    parse_frame,
    unpack_visual_alignment_payload,
)
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentResult


def test_visual_alignment_v3_roundtrip():
    obs = TargetObservation(
        timestamp_ms=123456,
        valid=True,
        class_id=0,
        class_name='person',
        confidence=0.923,
        cx=3200,
        cy=4880,
        w=2500,
        h=3000,
    )
    alignment = VisualAlignmentResult(
        state='ALIGN_LEFT',
        vy=-0.117,
        omega=0.0,
        reason='test',
        center_error=-0.36,
    )

    raw = pack_visual_alignment(123, obs, alignment, 456)
    frame = parse_frame(raw)
    assert frame['msg_type'] == MSG_VISUAL_ALIGNMENT
    assert frame['seq'] == 123
    assert frame['version'] == 3

    p = unpack_visual_alignment_payload(frame['payload'])
    assert p['alignment'] == 'ALIGN_LEFT'
    assert p['valid'] is True
    assert p['class_id'] == 0
    assert p['cx'] == 3200
    assert p['frame_id'] == 456
    assert abs(p['confidence'] - 0.923) < 0.001
    assert abs(p['vy_ref'] + 0.117) < 0.001
    assert abs(p['center_error'] + 0.36) < 0.001
