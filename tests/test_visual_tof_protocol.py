from src.comm.protocol import pack_visual_alignment, parse_frame, unpack_visual_alignment_payload, MSG_VISUAL_ALIGNMENT
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentResult


def test_visual_packet_roundtrip():
    obs = TargetObservation(
        timestamp_ms=100,
        valid=True,
        class_id=0,
        class_name='person',
        confidence=.91,
        cx=4200, cy=5000, w=2000, h=3000
    )
    a = VisualAlignmentResult(
        state='ALIGN_LEFT',
        vy=-.12,
        omega=0,
        center_error=-.16,
        reason='test'
    )

    raw = pack_visual_alignment(7, obs, a, 22)
    f = parse_frame(raw)
    assert f['msg_type'] == MSG_VISUAL_ALIGNMENT
    p = unpack_visual_alignment_payload(f['payload'])
    assert p['alignment'] == 'ALIGN_LEFT'
    assert abs(p['vy_ref'] + .12) < .002
    assert p['frame_id'] == 22
