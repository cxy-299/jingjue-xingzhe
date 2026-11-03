from dataclasses import dataclass


def clamp(value, low, high):
    return max(low, min(high, value))


@dataclass
class DistanceControlResult:
    state: str
    vx: float
    distance_mm: int
    distance_error_mm: int
    reason: str


class ToFDistanceController:
    """Front/back distance controller.

    In the real robot this logic belongs on ACG720 / soft-core side because
    ToF is part of the safety/execution layer, not the Raspberry Pi vision side.
    """

    def __init__(
        self,
        target_mm=500,
        deadband_mm=50,
        hard_stop_mm=250,
        max_vx=0.28,
        min_vx=0.04,
        kp=0.00035,
        smoothing_alpha=0.35,
    ):
        self.target_mm = int(target_mm)
        self.deadband_mm = max(0, int(deadband_mm))
        self.hard_stop_mm = max(0, int(hard_stop_mm))
        self.max_vx = abs(float(max_vx))
        self.min_vx = min(abs(float(min_vx)), self.max_vx)
        self.kp = max(0.0, float(kp))
        self.alpha = clamp(float(smoothing_alpha), 0.0, 1.0)
        self._vx = 0.0

    def _smooth(self, desired):
        self._vx = self._vx + self.alpha * (desired - self._vx)
        if abs(self._vx) < 1e-4:
            self._vx = 0.0
        return self._vx

    def reset(self):
        self._vx = 0.0

    def update(self, distance_mm: int, valid: bool = True):
        if not valid:
            self.reset()
            return DistanceControlResult(
                state='TOF_FAULT',
                vx=0.0,
                distance_mm=int(distance_mm),
                distance_error_mm=0,
                reason='ToF invalid -> forward motion forbidden',
            )

        d = int(distance_mm)
        error = d - self.target_mm

        if d <= self.hard_stop_mm:
            self.reset()
            return DistanceControlResult(
                state='HARD_STOP',
                vx=0.0,
                distance_mm=d,
                distance_error_mm=error,
                reason='distance below hard-stop threshold',
            )

        if d <= self.target_mm + self.deadband_mm:
            # Approach task: too close or inside target band means stop.
            self.reset()
            return DistanceControlResult(
                state='DISTANCE_OK',
                vx=0.0,
                distance_mm=d,
                distance_error_mm=error,
                reason='inside/closer than target distance band',
            )

        desired = self.kp * error
        desired = clamp(desired, self.min_vx, self.max_vx)
        vx = self._smooth(desired)

        return DistanceControlResult(
            state='APPROACH',
            vx=vx,
            distance_mm=d,
            distance_error_mm=error,
            reason='ToF distance too far -> approach',
        )
