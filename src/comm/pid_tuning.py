"""SIN12 R4 stopped-only wheel PID and atomic 10 ms wheel telemetry."""
import re
import struct
from src.comm.protocol import build_frame


def mission_lease_ms(version: int) -> int:
    """Explicit firmware contract, not a host-side override of board timing."""
    return 600 if version in (15, 16, 17, 18, 19, 20) else 300


def pack_pid_config(sequence: int, p: int, i: int, d: int) -> bytes:
    if any(type(v) is not int for v in (p, i, d)) or not (0 <= p <= 32 and 0 <= i <= 8 and 0 <= d <= 32):
        raise ValueError('P/D范围0–32，I范围0–8，均为整数')
    return build_frame(0x27, sequence, struct.pack('<HHH', p, i, d))


def parse_pid_status(line: str):
    if not re.fullmatch(r'K[0-9A-Fa-f]{14}', line.strip()):
        return None
    version, sequence, status, p, i, d = struct.unpack('>BHBBBB', bytes.fromhex(line.strip()[1:]))
    if version not in (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20) or status > 3 or p > 32 or i > 8 or d > 32:
        return None
    return dict(version=version, sequence=sequence, status=status, p=p, i=i, d=d)


def parse_control_status(line: str):
    if not re.fullmatch(r'O[0-9A-Fa-f]{10}', line.strip()):
        return None
    sequence, flags, state, reason, masks = bytes.fromhex(line.strip()[1:])
    if flags & 0xF0 or (flags >> 2) > 2 or state > 6 or reason > 8:
        return None
    blocked, severe = masks & 15, masks >> 4
    if blocked & severe:
        return None
    return dict(sequence=sequence, avoid_enabled=bool(flags & 1), avoid_captured=bool(flags & 2),
                recovery_result=flags >> 2, state=state, reason=reason,
                blocked_mask=blocked, severe_mask=severe)


def parse_wheel_sample(line: str):
    if not re.fullmatch(r'C[0-9A-Fa-f]{56}', line.strip()):
        return None
    values = struct.unpack('>HBhhb4B4h4H', bytes.fromhex(line.strip()[1:]))
    sequence, flags, reference, error, correction = values[:5]
    if flags & 0xF0 or (flags & 7) > 6:
        return None
    return dict(sequence=sequence, command=flags & 7, heading_locked=bool(flags & 8),
                reference_deg=reference * 180 / (8192 * 3.141592653589793),
                error_deg=error * 180 / (8192 * 3.141592653589793), correction=correction,
                targets=values[5:9], speeds=values[9:13], duties=values[13:17])
