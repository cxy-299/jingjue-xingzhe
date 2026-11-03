from dataclasses import dataclass
import math
from src.core.messages import TargetObservation


def clamp(value, low, high):
    return max(low, min(high, value))


@dataclass
class VisualAlignmentResult:
    state: str
    vy: float
    omega: float
    center_error: float
    reason: str


class VisualAlignmentController:
    """Vision only controls lateral alignment / target search.

    It DOES NOT decide forward/backward distance. Forward velocity vx is left
    to the ToF distance controller on the FPGA side (mocked on PC for now).
    """

    def __init__(
        self,
        center_target=5000,
        center_deadband=0.08,
        max_vy=0.22,
        lateral_gain=1.15,
        smoothing_alpha=0.35,
        search_omega=0.20,
        target_confirm_frames=2,
        lost_confirm_frames=2,
    ):
        self.center_target = float(center_target)
        if not math.isfinite(self.center_target) or not 0 <= self.center_target <= 10000:
            raise ValueError('center_target must be a finite camera coordinate in [0, 10000]')
        self.center_deadband = clamp(float(center_deadband), 0.0, 0.8)
        self.max_vy = abs(float(max_vy))
        self.lateral_gain = max(0.0, float(lateral_gain))
        self.smoothing_alpha = clamp(float(smoothing_alpha), 0.0, 1.0)
        self.search_omega = float(search_omega)
        self.target_confirm_frames = max(1, int(target_confirm_frames))
        self.lost_confirm_frames = max(1, int(lost_confirm_frames))

        self._valid_count = 0
        self._lost_count = 0
        self._vy = 0.0

    def _horizontal_error(self, cx: int) -> float:
        return clamp((float(cx) - self.center_target) / 5000.0, -1.0, 1.0)

    def _deadband_map(self, error: float) -> float:
        a = abs(error)
        if a <= self.center_deadband:
            return 0.0
        mapped = (a - self.center_deadband) / max(1e-6, 1.0 - self.center_deadband)
        return mapped if error > 0 else -mapped

    def _smooth(self, desired: float) -> float:
        a = self.smoothing_alpha
        self._vy = self._vy + a * (desired - self._vy)
        if abs(self._vy) < 1e-4:
            self._vy = 0.0
        return self._vy

    def update(self, obs: TargetObservation) -> VisualAlignmentResult:
        if not obs.valid:
            self._valid_count = 0
            self._lost_count += 1
            self._vy = 0.0

            if self._lost_count < self.lost_confirm_frames:
                return VisualAlignmentResult(
                    state='HOLD',
                    vy=0.0,
                    omega=0.0,
                    center_error=0.0,
                    reason='target lost; waiting confirmation',
                )

            return VisualAlignmentResult(
                state='SEARCH',
                vy=0.0,
                omega=self.search_omega,
                center_error=0.0,
                reason='no valid target -> search rotation',
            )

        self._lost_count = 0
        self._valid_count += 1

        if self._valid_count < self.target_confirm_frames:
            self._vy = 0.0
            return VisualAlignmentResult(
                state='HOLD',
                vy=0.0,
                omega=0.0,
                center_error=0.0,
                reason='confirming target',
            )

        ex = self._horizontal_error(obs.cx)
        ex_cmd = self._deadband_map(ex)

        desired_vy = clamp(
            self.lateral_gain * ex_cmd * self.max_vy,
            -self.max_vy,
            self.max_vy,
        )
        vy = self._smooth(desired_vy)

        if ex_cmd < 0:
            state = 'ALIGN_LEFT'
        elif ex_cmd > 0:
            state = 'ALIGN_RIGHT'
        else:
            state = 'CENTERED'

        return VisualAlignmentResult(
            state=state,
            vy=vy,
            omega=0.0,
            center_error=ex,
            reason='vision lateral alignment only',
        )
