import struct
from src.core.messages import TargetObservation

HEADER = b'\xAA\x55'
VERSION = 3

MSG_HEARTBEAT = 0x01
MSG_TARGET = 0x10
MSG_VISUAL_ALIGNMENT = 0x12
MSG_VISION_RESULT = 0x13
MSG_LOCKED_TARGET = 0x14
MSG_NAV_GOAL = 0x20
MSG_NAV_PATH = 0x21
MSG_TURN_RELATIVE = 0x22
NAV_MAP_ID = 0x2601

VISION_FLAG_VALID = 0x01
VISION_FLAG_CONFIRMED = 0x02
VISION_FLAG_CENTERED = 0x04

ALIGN_TO_ID = {
    'HOLD': 0x00,
    'SEARCH': 0x01,
    'ALIGN_LEFT': 0x02,
    'ALIGN_RIGHT': 0x03,
    'CENTERED': 0x04,
    'ERROR': 0xFF,
}
ID_TO_ALIGN = {v: k for k, v in ALIGN_TO_ID.items()}


def crc16_ccitt(data: bytes, init=0xFFFF):
    crc = init
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = (((crc << 1) ^ 0x1021) & 0xFFFF) if crc & 0x8000 else ((crc << 1) & 0xFFFF)
    return crc


def build_frame(msg_type, seq, payload):
    body = struct.pack('<BBHH', VERSION, msg_type & 0xFF, seq & 0xFFFF, len(payload)) + payload
    return HEADER + body + struct.pack('<H', crc16_ccitt(body))


def pack_heartbeat(seq, uptime_ms):
    return build_frame(MSG_HEARTBEAT, seq, struct.pack('<I', uptime_ms & 0xFFFFFFFF))


def pack_nav_goal(seq: int, goal_x: int, goal_y: int, map_id: int = NAV_MAP_ID) -> bytes:
    """发送 20×20 地图格坐标，不发送路径或电机速度；路径由 FPGA 计算。"""
    if not (0 <= goal_x < 20 and 0 <= goal_y < 20):
        raise ValueError('Goal cell must be inside the 20x20 map')
    if map_id != NAV_MAP_ID:
        raise ValueError('Unsupported fixed map ID')
    return build_frame(MSG_NAV_GOAL, seq, struct.pack('<HBB', map_id, goal_x, goal_y))


def pack_turn_relative(seq: int, angle_deg: float, speed: int = 12,
                       yaw_inverted: bool = False) -> bytes:
    """SIN10: FPGA relative yaw control; positive angle is physical CCW.

    The GUI sends a target once and renews G, never computes wheel/PWM output.
    A separate S and neutral interval are required before every new turn.
    """
    import math
    if isinstance(angle_deg, bool) or not math.isfinite(angle_deg):
        raise ValueError('Turn angle must be finite')
    centidegrees = round(angle_deg * 100)
    if not 500 <= abs(centidegrees) <= 18000:
        raise ValueError('Turn angle must be 5..180 degrees in either direction')
    if type(speed) is not int or not 8 <= speed <= 12:
        raise ValueError('Turn speed must be an integer in 8..12')
    return build_frame(MSG_TURN_RELATIVE, seq,
                       struct.pack('<hBB', centidegrees, speed, int(bool(yaw_inverted))))


def pack_nav_path(seq: int, goal_x: int, goal_y: int, directions,
                  map_id: int = NAV_MAP_ID) -> bytes:
    """Pack a validated grid path for the FPGA route executor.

    ``directions`` contains one byte/code per 10 cm step: 0=forward,
    1=backward, 2=left, 3=right.  The FPGA validates the fixed map ID,
    CRC and direction range before accepting the route.
    """
    if not (0 <= goal_x < 20 and 0 <= goal_y < 20):
        raise ValueError('Goal cell must be inside the 20x20 map')
    if map_id != NAV_MAP_ID:
        raise ValueError('Unsupported fixed map ID')
    codes = bytes(int(code) for code in directions)
    if len(codes) > 64:
        raise ValueError('Navigation path is limited to 64 steps')
    if any(code > 3 for code in codes):
        raise ValueError('Navigation direction code must be 0..3')
    payload = struct.pack('<HBBB', map_id, goal_x, goal_y, len(codes)) + codes
    return build_frame(MSG_NAV_PATH, seq, payload)


def pack_target(seq, obs: TargetObservation):
    conf = max(0, min(10000, int(round(obs.confidence * 10000))))
    payload = struct.pack(
        '<IBHHHHHH',
        obs.timestamp_ms & 0xFFFFFFFF,
        1 if obs.valid else 0,
        obs.class_id & 0xFFFF,
        conf,
        obs.cx & 0xFFFF,
        obs.cy & 0xFFFF,
        obs.w & 0xFFFF,
        obs.h & 0xFFFF,
    )
    return build_frame(MSG_TARGET, seq, payload)


def pack_visual_alignment(seq, obs: TargetObservation, alignment, frame_id: int):
    conf = max(0, min(10000, int(round(obs.confidence * 10000))))
    align_id = ALIGN_TO_ID.get(getattr(alignment, 'state', 'ERROR'), ALIGN_TO_ID['ERROR'])

    # vy is serialized as signed mm/s, center error as signed -10000..10000.
    vy_mm_s = max(-32768, min(32767, int(round(alignment.vy * 1000.0))))
    ex_10000 = max(-10000, min(10000, int(round(alignment.center_error * 10000.0))))

    payload = struct.pack(
        '<IBBHHHHHHhhI',
        obs.timestamp_ms & 0xFFFFFFFF,
        1 if obs.valid else 0,
        align_id & 0xFF,
        obs.class_id & 0xFFFF,
        conf,
        obs.cx & 0xFFFF,
        obs.cy & 0xFFFF,
        obs.w & 0xFFFF,
        obs.h & 0xFFFF,
        vy_mm_s,
        ex_10000,
        frame_id & 0xFFFFFFFF,
    )
    return build_frame(MSG_VISUAL_ALIGNMENT, seq, payload)


def pack_vision_result(seq, obs: TargetObservation, alignment, frame_id: int):
    """Pack perception-only data for the FPGA control system.

    Raspberry Pi reports what YOLO saw. It deliberately does not send motor
    speed/PWM commands: the FPGA owns target following, ToF safety, motion
    control, encoder PID and the watchdog.
    """
    confidence = max(0, min(10000, int(round(obs.confidence * 10000))))
    alignment_name = getattr(alignment, 'state', 'ERROR')
    alignment_id = ALIGN_TO_ID.get(alignment_name, ALIGN_TO_ID['ERROR'])

    flags = VISION_FLAG_VALID if obs.valid else 0
    if obs.valid and alignment_name not in ('HOLD', 'ERROR'):
        flags |= VISION_FLAG_CONFIRMED
    if obs.valid and alignment_name == 'CENTERED':
        flags |= VISION_FLAG_CENTERED

    center_error = max(
        -10000,
        min(10000, int(round(getattr(alignment, 'center_error', 0.0) * 10000.0))),
    )
    area_ratio = max(
        0,
        min(10000, int(round((obs.w * obs.h) / 10000.0))),
    )

    payload = struct.pack(
        '<IIBBHHHHHHhH',
        obs.timestamp_ms & 0xFFFFFFFF,
        frame_id & 0xFFFFFFFF,
        flags,
        alignment_id & 0xFF,
        obs.class_id & 0xFFFF,
        confidence,
        obs.cx & 0xFFFF,
        obs.cy & 0xFFFF,
        obs.w & 0xFFFF,
        obs.h & 0xFFFF,
        center_error,
        area_ratio,
    )
    return build_frame(MSG_VISION_RESULT, seq, payload)


def pack_locked_target(seq, obs, alignment, frame_id, lock_id=0, follow=False,
                       confirmed=False):
    """SIN9: CRC-protected perception + explicit selection/follow intent.

    Base 26-byte perception payload followed by uint32 lock ID. Flags:
    bit0 visible, bit1 confirmed, bit2 centered, bit3 selected, bit4 follow.
    No motor/PWM bytes. Absent target retains selected class/lock identity.
    """
    base = parse_frame(pack_vision_result(seq, obs, alignment, frame_id))['payload']
    payload = bytearray(base)
    payload[8] = ((1 if obs.valid else 0) | (2 if obs.valid and confirmed else 0)
                  | (4 if obs.valid and abs(alignment.center_error) <= 0.12 else 0)
                  | (8 if lock_id else 0) | (16 if follow and lock_id else 0))
    return build_frame(MSG_LOCKED_TARGET, seq, bytes(payload) + struct.pack('<I', lock_id))


def pack_mission_observation(seq, obs, alignment, frame_id, lock_id, confirmed,
                             mission_id, color='any'):
    if type(mission_id) is not int or not 1 <= mission_id <= 0xffffffff:
        raise ValueError('Invalid mission ID')
    if color not in ('any', 'red'):
        raise ValueError('Invalid mission color')
    base = parse_frame(pack_locked_target(seq, obs, alignment, frame_id,
                                         lock_id, True, confirmed))['payload']
    return build_frame(0x15, seq, base + struct.pack('<IB', mission_id, color == 'red'))


def pack_visual_primary_observation(seq, obs, alignment, frame_id, lock_id,
                                    confirmed, mission_id, color='any', geometry=None):
    """0x16 = original35 bytes + flags/yaw_cdeg/coarse/uncertainty/age.

    Unsupported R12 ignores this type. Invalid geometry is an explicit HOLD,
    never a legacy0x15 fallback that might accidentally authorize old motion.
    Age includes inference time at the caller; FPGA adds a20ms transport margin.
    """
    base = parse_frame(pack_mission_observation(seq, obs, alignment, frame_id,
                                              lock_id, confirmed, mission_id, color))['payload']
    flags, yaw, coarse, uncertainty, age = 0,0,0,0,65535
    if geometry is not None and obs.valid and confirmed and lock_id:
        yaw, coarse, uncertainty, age = (geometry[k] for k in
            ('yaw_left_cdeg','coarse_mm','uncertainty_mm','observation_age_ms'))
        if (any(type(v) is not int for v in (yaw,coarse,uncertainty,age))
                or not -4500<=yaw<=4500 or not 150<=coarse<=10000
                or not 20<=uncertainty<=coarse//2 or not 0<=age<280):
            raise ValueError('Invalid visual-primary geometry')
        flags = 1 | (2 if geometry.get('beam_inside') else 0)
    return build_frame(0x16, seq, base+struct.pack('<BhHHH',flags,yaw,coarse,uncertainty,age))


def pack_mission_request(seq, mission_id, class_id, distance_mm=200,
                         color='any', yaw_inverted=False):
    if type(mission_id) is not int or not 1 <= mission_id <= 0xffffffff:
        raise ValueError('Invalid mission ID')
    if type(class_id) is not int or not 0 <= class_id < 65535:
        raise ValueError('Invalid class ID')
    if type(distance_mm) is not int or not 180 <= distance_mm <= 1000:
        raise ValueError('Arrival distance must be 180..1000 mm')
    if color not in ('any', 'red') or type(yaw_inverted) is not bool:
        raise ValueError('Invalid mission flags')
    return build_frame(0x24, seq, struct.pack('<IHHBB', mission_id, class_id,
                       distance_mm, color == 'red', yaw_inverted))


def parse_frame(frame):
    if len(frame) < 10 or frame[:2] != HEADER:
        raise ValueError('Bad frame header')

    version, msg_type, seq, n = struct.unpack('<BBHH', frame[2:8])
    if len(frame) != 10 + n:
        raise ValueError(f'Bad length: actual={len(frame)}, expected={10+n}')

    payload = frame[8:8+n]
    recv_crc = struct.unpack('<H', frame[-2:])[0]
    calc_crc = crc16_ccitt(frame[2:-2])
    if recv_crc != calc_crc:
        raise ValueError(f'CRC mismatch: recv=0x{recv_crc:04X}, calc=0x{calc_crc:04X}')

    return {
        'version': version,
        'msg_type': msg_type,
        'seq': seq,
        'payload': payload,
    }


def unpack_heartbeat_payload(payload):
    if len(payload) != 4:
        raise ValueError('Bad heartbeat payload length')
    return {'uptime_ms': struct.unpack('<I', payload)[0]}


def unpack_visual_alignment_payload(payload):
    fmt = '<IBBHHHHHHhhI'
    if len(payload) != struct.calcsize(fmt):
        raise ValueError(f'Bad visual alignment payload length: {len(payload)}')

    (
        timestamp_ms, valid, align_id, class_id, conf,
        cx, cy, w, h, vy_mm_s, ex_10000, frame_id
    ) = struct.unpack(fmt, payload)

    return {
        'timestamp_ms': timestamp_ms,
        'valid': bool(valid),
        'alignment_id': align_id,
        'alignment': ID_TO_ALIGN.get(align_id, f'UNKNOWN_0x{align_id:02X}'),
        'class_id': class_id,
        'confidence': conf / 10000.0,
        'cx': cx,
        'cy': cy,
        'w': w,
        'h': h,
        'vy_ref': vy_mm_s / 1000.0,
        'center_error': ex_10000 / 10000.0,
        'frame_id': frame_id,
    }


def unpack_vision_result_payload(payload):
    fmt = '<IIBBHHHHHHhH'
    if len(payload) != struct.calcsize(fmt):
        raise ValueError(f'Bad vision result payload length: {len(payload)}')

    (
        timestamp_ms, frame_id, flags, alignment_id, class_id, confidence,
        cx, cy, w, h, center_error, area_ratio
    ) = struct.unpack(fmt, payload)

    return {
        'timestamp_ms': timestamp_ms,
        'frame_id': frame_id,
        'flags': flags,
        'valid': bool(flags & VISION_FLAG_VALID),
        'confirmed': bool(flags & VISION_FLAG_CONFIRMED),
        'centered': bool(flags & VISION_FLAG_CENTERED),
        'alignment_id': alignment_id,
        'alignment': ID_TO_ALIGN.get(
            alignment_id, f'UNKNOWN_0x{alignment_id:02X}'
        ),
        'class_id': class_id,
        'confidence': confidence / 10000.0,
        'cx': cx,
        'cy': cy,
        'w': w,
        'h': h,
        'center_error': center_error / 10000.0,
        'area_ratio': area_ratio / 10000.0,
    }
