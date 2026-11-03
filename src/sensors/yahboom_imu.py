"""Yahboom 10-axis IMU UART frame parser.

The module uses the documented 11-byte frame format::

    55 TYPE D0 D1 D2 D3 D4 D5 D6 D7 CHECKSUM

All data words are little-endian signed 16-bit values and the checksum is the
low byte of the sum of the first ten bytes.  The parser is deliberately
stream-oriented so it can recover after a dropped byte or line noise.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Optional, Tuple


def _s16(lo: int, hi: int) -> int:
    value = lo | (hi << 8)
    return value - 0x10000 if value & 0x8000 else value


@dataclass(frozen=True)
class YahboomImuFrame:
    frame_type: int
    raw: Tuple[int, int, int, int]
    roll_deg: Optional[float] = None
    pitch_deg: Optional[float] = None
    yaw_deg: Optional[float] = None

    @property
    def kind(self) -> str:
        return {0x50: "time", 0x51: "accel", 0x52: "gyro", 0x53: "angle",
                0x54: "mag", 0x55: "port", 0x56: "pressure",
                0x57: "quat", 0x58: "gps"}.get(self.frame_type, "unknown")


class YahboomImuParser:
    """Incremental parser; ``feed`` returns only checksum-valid frames."""

    FRAME_LEN = 11
    HEADER = 0x55

    def __init__(self) -> None:
        self._buffer = bytearray()
        self.frames_ok = 0
        self.frames_bad = 0

    def feed(self, data: bytes | bytearray | Iterable[int]) -> List[YahboomImuFrame]:
        self._buffer.extend(int(b) & 0xFF for b in data)
        frames: List[YahboomImuFrame] = []
        while True:
            try:
                start = self._buffer.index(self.HEADER)
            except ValueError:
                self._buffer.clear()
                break
            if start:
                del self._buffer[:start]
            if len(self._buffer) < self.FRAME_LEN:
                break
            raw = bytes(self._buffer[:self.FRAME_LEN])
            if (sum(raw[:10]) & 0xFF) != raw[10]:
                self.frames_bad += 1
                del self._buffer[0]
                continue
            del self._buffer[:self.FRAME_LEN]
            frame_type = raw[1]
            words = tuple(_s16(raw[i], raw[i + 1]) for i in (2, 4, 6, 8))
            kwargs = {}
            if frame_type == 0x53:
                kwargs = {
                    "roll_deg": words[0] / 32768.0 * 180.0,
                    "pitch_deg": words[1] / 32768.0 * 180.0,
                    "yaw_deg": words[2] / 32768.0 * 180.0,
                }
            frame = YahboomImuFrame(frame_type, words, **kwargs)
            self.frames_ok += 1
            frames.append(frame)
        return frames

    def reset(self) -> None:
        self._buffer.clear()
        self.frames_ok = 0
        self.frames_bad = 0


def build_frame(frame_type: int, words: Tuple[int, int, int, int]) -> bytes:
    """Build a protocol frame for tests and deterministic hardware bring-up."""
    payload = bytearray((0x55, frame_type & 0xFF))
    for value in words:
        value &= 0xFFFF
        payload.extend((value & 0xFF, (value >> 8) & 0xFF))
    payload.append(sum(payload) & 0xFF)
    return bytes(payload)
