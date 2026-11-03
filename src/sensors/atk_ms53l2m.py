"""ATK-MS53L2M ASCII UART parsing and four-sensor safety policy."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Optional, Sequence


@dataclass(frozen=True)
class ToFReading:
    distance_mm: int


class ATKMS53L2MParser:
    """Parse normal-mode distance lines such as ``800\r\n``.

    Signal-strength and multi-target variants are tolerated: only the first
    integer token is used. Values outside the module's 40..8000 mm range are
    rejected instead of being allowed to clear an obstacle stop.
    """

    def __init__(self, min_mm: int = 40, max_mm: int = 8000) -> None:
        self.min_mm = min_mm
        self.max_mm = max_mm
        self._line = bytearray()
        self.invalid_lines = 0

    def feed(self, data: bytes | bytearray | Iterable[int]) -> List[ToFReading]:
        readings: List[ToFReading] = []
        for value in data:
            byte = int(value) & 0xFF
            if byte in (0x0D, 0x0A):
                if self._line:
                    reading = self._parse_line(bytes(self._line))
                    if reading is None:
                        self.invalid_lines += 1
                    else:
                        readings.append(reading)
                    self._line.clear()
                continue
            if len(self._line) < 32:
                self._line.append(byte)
            else:
                self._line.clear()
                self.invalid_lines += 1
        return readings

    def _parse_line(self, line: bytes) -> Optional[ToFReading]:
        token = bytearray()
        for byte in line:
            if 48 <= byte <= 57:
                token.append(byte)
            elif token:
                break
            elif byte in (ord(" "), ord("\t")):
                continue
            else:
                return None
        if not token:
            return None
        distance = int(token.decode("ascii"))
        if not self.min_mm <= distance <= self.max_mm:
            return None
        return ToFReading(distance)


@dataclass(frozen=True)
class ToFSafetyDecision:
    state: str
    min_distance_mm: Optional[int]
    speed_scale_permille: int
    valid_count: int


class MultiToFSafetyGuard:
    """Conservative obstacle policy shared by GUI simulation and FPGA RTL.

    ``hard_stop_mm`` is an immediate stop. Between hard-stop and deceleration
    thresholds the requested speed is linearly limited. If no sensor is valid,
    the safe result is ``TOF_FAULT`` with zero speed.
    """

    def __init__(self, hard_stop_mm: int = 250, decel_mm: int = 500,
                 clear_mm: int = 800) -> None:
        if not (0 < hard_stop_mm < decel_mm < clear_mm):
            raise ValueError("thresholds must satisfy 0 < hard < decel < clear")
        self.hard_stop_mm = hard_stop_mm
        self.decel_mm = decel_mm
        self.clear_mm = clear_mm

    def update(self, distances_mm: Sequence[Optional[int]]) -> ToFSafetyDecision:
        valid = [int(d) for d in distances_mm if d is not None and int(d) > 0]
        if not valid:
            return ToFSafetyDecision("TOF_FAULT", None, 0, 0)
        nearest = min(valid)
        if nearest <= self.hard_stop_mm:
            return ToFSafetyDecision("HARD_STOP", nearest, 0, len(valid))
        if nearest < self.decel_mm:
            span = self.decel_mm - self.hard_stop_mm
            scale = ((nearest - self.hard_stop_mm) * 400) // span + 100
            return ToFSafetyDecision("DECEL", nearest, min(500, max(100, scale)), len(valid))
        if nearest < self.clear_mm:
            span = self.clear_mm - self.decel_mm
            scale = 500 + ((nearest - self.decel_mm) * 500) // span
            return ToFSafetyDecision("CLEAR_LIMITED", nearest, min(1000, scale), len(valid))
        return ToFSafetyDecision("CLEAR", nearest, 1000, len(valid))
