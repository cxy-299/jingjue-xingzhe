from dataclasses import dataclass
from src.core.messages import TargetObservation


def clamp(value, low, high):
    return max(low, min(high, value))


@dataclass
class DecisionResult:
    action: str
    vx: float
    vy: float
    omega: float
    area_ratio: float
    reason: str
    center_error: float = 0.0
    distance_error: float = 0.0


class DecisionSimulator:
    """Continuous PC-side visual tracking controller.

    This module is still a SIMULATOR.  It generates a chassis-level reference
    (vx, vy, omega), not motor PWM.  In the real robot ACG720 must still apply
    ToF / emergency-stop / watchdog safety checks before executing any command.

    Control idea:
      - horizontal image error -> continuous lateral velocity vy
      - target box area error    -> continuous forward velocity vx
      - both are calculated at the same time, so the mecanum chassis can
        approach diagonally while centering the target.
      - close-range STOP uses area only during PC tests.  On the real robot,
        ToF should replace area as the authoritative stopping-distance source.
    """

    def __init__(
        self,
        center_target=5000,
        center_deadband=0.08,
        stop_area_ratio=0.12,
        resume_area_ratio=0.10,
        search_omega=0.20,
        max_vx=0.28,
        min_vx=0.04,
        max_vy=0.22,
        lateral_gain=1.15,
        approach_gain=1.10,
        omega_gain=0.0,
        max_omega=0.15,
        smoothing_alpha=0.35,
        target_confirm_frames=2,
        lost_confirm_frames=2,
        # Backward-compatible arguments from the older discrete controller.
        center_low=None,
        center_high=None,
        align_speed=None,
        approach_speed=None,
        stable_frames=None,
    ):
        # If an old config is used, infer the center and deadband from it.
        if center_low is not None and center_high is not None:
            center_target = (int(center_low) + int(center_high)) / 2.0
            half_band = (int(center_high) - int(center_low)) / 2.0
            center_deadband = half_band / 5000.0

        if align_speed is not None:
            max_vy = float(align_speed)
        if approach_speed is not None:
            max_vx = float(approach_speed)
        if stable_frames is not None:
            target_confirm_frames = int(stable_frames)

        self.center_target = float(center_target)
        self.center_deadband = clamp(float(center_deadband), 0.0, 0.8)

        self.stop_area_ratio = float(stop_area_ratio)
        self.resume_area_ratio = min(float(resume_area_ratio), self.stop_area_ratio)

        self.search_omega = float(search_omega)
        self.max_vx = abs(float(max_vx))
        self.min_vx = clamp(abs(float(min_vx)), 0.0, self.max_vx)
        self.max_vy = abs(float(max_vy))
        self.lateral_gain = max(0.0, float(lateral_gain))
        self.approach_gain = max(0.0, float(approach_gain))

        self.omega_gain = float(omega_gain)
        self.max_omega = abs(float(max_omega))
        self.smoothing_alpha = clamp(float(smoothing_alpha), 0.0, 1.0)

        self.target_confirm_frames = max(1, int(target_confirm_frames))
        self.lost_confirm_frames = max(1, int(lost_confirm_frames))

        self._valid_count = 0
        self._lost_count = 0
        self._near_latched = False

        self._vx = 0.0
        self._vy = 0.0
        self._omega = 0.0

    @staticmethod
    def _area_ratio(obs: TargetObservation) -> float:
        if not obs.valid:
            return 0.0
        return (obs.w / 10000.0) * (obs.h / 10000.0)

    def _horizontal_error(self, cx: int) -> float:
        # Approximately -1 at far left, 0 at center, +1 at far right.
        return clamp((float(cx) - self.center_target) / 5000.0, -1.0, 1.0)

    def _deadband_map(self, error: float) -> float:
        """Remove center jitter while preserving continuous control outside it."""
        a = abs(error)
        if a <= self.center_deadband:
            return 0.0

        # Remap the remaining range continuously back to 0..1.
        remapped = (a - self.center_deadband) / max(1e-6, 1.0 - self.center_deadband)
        return remapped if error > 0 else -remapped

    def _smooth(self, old: float, desired: float) -> float:
        a = self.smoothing_alpha
        return old + a * (desired - old)

    def _zero_motion(self):
        self._vx = 0.0
        self._vy = 0.0
        self._omega = 0.0

    def update(self, obs: TargetObservation) -> DecisionResult:
        # ---------- target lost: never keep the previous forward command ----------
        if not obs.valid:
            self._valid_count = 0
            self._lost_count += 1
            self._near_latched = False
            self._zero_motion()

            if self._lost_count < self.lost_confirm_frames:
                return DecisionResult(
                    action='HOLD',
                    vx=0.0, vy=0.0, omega=0.0,
                    area_ratio=0.0,
                    reason=(
                        f'target lost; waiting confirmation '
                        f'({self._lost_count}/{self.lost_confirm_frames})'
                    ),
                )

            self._omega = self.search_omega
            return DecisionResult(
                action='SEARCH',
                vx=0.0, vy=0.0, omega=self._omega,
                area_ratio=0.0,
                reason='no valid target -> safe search rotation',
            )

        # ---------- target reacquisition confirmation ----------
        self._lost_count = 0
        self._valid_count += 1
        if self._valid_count < self.target_confirm_frames:
            self._zero_motion()
            return DecisionResult(
                action='HOLD',
                vx=0.0, vy=0.0, omega=0.0,
                area_ratio=self._area_ratio(obs),
                reason=(
                    f'confirming target '
                    f'({self._valid_count}/{self.target_confirm_frames})'
                ),
            )

        area = self._area_ratio(obs)
        ex = self._horizontal_error(obs.cx)
        ex_cmd = self._deadband_map(ex)

        # Hysteresis prevents APPROACH/STOP chatter near the area threshold.
        if area >= self.stop_area_ratio:
            self._near_latched = True
        elif area <= self.resume_area_ratio:
            self._near_latched = False

        # ---------- lateral continuous control ----------
        lateral_norm = clamp(self.lateral_gain * ex_cmd, -1.0, 1.0)
        desired_vy = self.max_vy * lateral_norm

        # Optional yaw correction. Default is zero because mecanum lateral
        # translation is preferred during the current PC/person test.
        yaw_norm = clamp(self.omega_gain * ex_cmd, -1.0, 1.0)
        desired_omega = self.max_omega * yaw_norm

        # ---------- forward continuous control ----------
        # Positive error means target looks smaller than the desired stop size.
        distance_error = clamp(
            (self.stop_area_ratio - area) / max(1e-6, self.stop_area_ratio),
            -1.0,
            1.0,
        )

        if self._near_latched:
            desired_vx = 0.0
        else:
            desired_vx = self.max_vx * clamp(
                self.approach_gain * max(0.0, distance_error),
                0.0,
                1.0,
            )
            # Prevent an impractically tiny crawl while still outside the
            # stopping hysteresis region.
            if desired_vx > 0.0:
                desired_vx = max(self.min_vx, desired_vx)

        # ---------- output smoothing ----------
        # If we are too close, forward velocity must become zero immediately.
        if self._near_latched:
            self._vx = 0.0
        else:
            self._vx = self._smooth(self._vx, desired_vx)

        self._vy = self._smooth(self._vy, desired_vy)
        self._omega = self._smooth(self._omega, desired_omega)

        if abs(self._vy) < 0.002:
            self._vy = 0.0
        if abs(self._omega) < 0.002:
            self._omega = 0.0

        # ---------- human-readable state label ----------
        if self._near_latched:
            if ex_cmd < 0:
                action = 'ALIGN_LEFT'
            elif ex_cmd > 0:
                action = 'ALIGN_RIGHT'
            else:
                action = 'STOP'
        else:
            if ex_cmd < 0:
                action = 'APPROACH_LEFT'
            elif ex_cmd > 0:
                action = 'APPROACH_RIGHT'
            else:
                action = 'APPROACH'

        return DecisionResult(
            action=action,
            vx=self._vx,
            vy=self._vy,
            omega=self._omega,
            area_ratio=area,
            center_error=ex,
            distance_error=distance_error,
            reason=(
                f'ex={ex:+.3f}, area={area:.3f}, '
                f'dist_err={distance_error:+.3f}, near={self._near_latched}'
            ),
        )
