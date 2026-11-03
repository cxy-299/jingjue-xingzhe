"""安全的目标跟随参考控制器。

该模块只生成底盘参考速度，不直接写 PWM。视觉检测提供目标横向偏差，
车头 ToF 提供与目标的前向距离，IMU 提供航向保持；任一安全输入失效时
输出停车。真正的电机执行仍必须经过 FPGA 的 ToF、编码器和看门狗门控。
"""

from __future__ import annotations

from dataclasses import dataclass
import math


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def wrap_degrees(value: float) -> float:
    """把角度差归一化到 [-180, 180)。"""
    return (value + 180.0) % 360.0 - 180.0


@dataclass(frozen=True)
class FollowResult:
    state: str
    vx: float
    vy: float
    omega: float
    distance_mm: int
    distance_error_mm: int
    center_error: float
    yaw_error_deg: float
    reason: str


class FollowController:
    """用视觉横向误差、ToF 距离和 IMU 航向生成跟随参考。

    ``center_error`` 约定为 -1..1：目标在画面左侧为负、右侧为正。
    默认目标距离为 300 mm。控制器不接受目标丢失或 IMU/ToF 无效时的
    盲行驶；这使它可以直接作为上层策略状态机的安全核心。
    """

    def __init__(
        self,
        target_mm: int = 300,
        distance_deadband_mm: int = 25,
        hard_stop_mm: int = 250,
        max_forward: float = 0.18,
        max_reverse: float = 0.10,
        max_lateral: float = 0.16,
        max_omega: float = 0.20,
        distance_gain: float = 0.0012,
        lateral_gain: float = 0.22,
        yaw_gain: float = 0.018,
        center_deadband: float = 0.06,
        yaw_deadband_deg: float = 2.0,
        smoothing_alpha: float = 0.35,
        require_imu: bool = True,
    ):
        self.target_mm = int(target_mm)
        self.deadband_mm = max(0, int(distance_deadband_mm))
        self.hard_stop_mm = max(0, int(hard_stop_mm))
        self.max_forward = abs(float(max_forward))
        self.max_reverse = abs(float(max_reverse))
        self.max_lateral = abs(float(max_lateral))
        self.max_omega = abs(float(max_omega))
        self.distance_gain = max(0.0, float(distance_gain))
        self.lateral_gain = max(0.0, float(lateral_gain))
        self.yaw_gain = max(0.0, float(yaw_gain))
        self.center_deadband = clamp(float(center_deadband), 0.0, 0.8)
        self.yaw_deadband_deg = max(0.0, float(yaw_deadband_deg))
        self.alpha = clamp(float(smoothing_alpha), 0.0, 1.0)
        self.require_imu = bool(require_imu)
        self._yaw_reference: float | None = None
        self._vx = 0.0
        self._vy = 0.0
        self._omega = 0.0

    def lock(self, yaw_deg: float | None = None) -> None:
        """锁定当前目标并记录航向基准。"""
        self._yaw_reference = None if yaw_deg is None else float(yaw_deg)
        self.reset_motion()

    def unlock(self) -> None:
        self._yaw_reference = None
        self.reset_motion()

    def reset_motion(self) -> None:
        self._vx = self._vy = self._omega = 0.0

    def _smooth(self, old: float, desired: float) -> float:
        return old + self.alpha * (desired - old)

    def update(
        self,
        *,
        target_valid: bool,
        center_error: float = 0.0,
        distance_mm: int = 0,
        tof_valid: bool,
        imu_valid: bool,
        yaw_deg: float | None = None,
    ) -> FollowResult:
        center = clamp(float(center_error), -1.0, 1.0)
        distance = int(distance_mm)
        yaw_error = 0.0

        if not target_valid:
            self.reset_motion()
            return FollowResult(
                "TARGET_LOST", 0.0, 0.0, 0.0, distance, 0, center, 0.0,
                "目标丢失，等待重新确认，不盲行驶",
            )
        if not tof_valid:
            self.reset_motion()
            return FollowResult(
                "TOF_FAULT", 0.0, 0.0, 0.0, distance, 0, center, 0.0,
                "ToF 无效，安全停车",
            )
        if self.require_imu and not imu_valid:
            self.reset_motion()
            return FollowResult(
                "IMU_FAULT", 0.0, 0.0, 0.0, distance, 0, center, 0.0,
                "IMU 无效，安全停车",
            )
        if distance <= self.hard_stop_mm:
            self.reset_motion()
            return FollowResult(
                "HARD_STOP", 0.0, 0.0, 0.0, distance,
                distance - self.target_mm, center, 0.0,
                "距离进入硬停车区",
            )

        if self._yaw_reference is None and yaw_deg is not None:
            self._yaw_reference = float(yaw_deg)
        if yaw_deg is not None and self._yaw_reference is not None:
            yaw_error = wrap_degrees(float(yaw_deg) - self._yaw_reference)

        distance_error = distance - self.target_mm
        if abs(distance_error) <= self.deadband_mm:
            desired_vx = 0.0
        elif distance_error > 0:
            desired_vx = clamp(self.distance_gain * distance_error,
                               0.0, self.max_forward)
        else:
            desired_vx = clamp(self.distance_gain * distance_error,
                               -self.max_reverse, 0.0)

        center_cmd = 0.0 if abs(center) <= self.center_deadband else center
        desired_vy = clamp(self.lateral_gain * center_cmd,
                           -self.max_lateral, self.max_lateral)
        yaw_cmd = 0.0 if abs(yaw_error) <= self.yaw_deadband_deg else yaw_error
        desired_omega = clamp(-self.yaw_gain * yaw_cmd,
                              -self.max_omega, self.max_omega)

        # Reaching the distance deadband is a stop condition, not another
        # acceleration setpoint. Letting the IIR tail decay while still issuing
        # F/B can carry the chassis past the requested stand-off distance.
        self._vx = 0.0 if desired_vx == 0 else self._smooth(self._vx, desired_vx)
        self._vy = self._smooth(self._vy, desired_vy)
        self._omega = self._smooth(self._omega, desired_omega)
        if abs(self._vx) < 0.002:
            self._vx = 0.0
        if abs(self._vy) < 0.002:
            self._vy = 0.0
        if abs(self._omega) < 0.002:
            self._omega = 0.0

        state = "HOLD_300MM" if desired_vx == 0 and desired_vy == 0 and desired_omega == 0 else "FOLLOW"
        return FollowResult(
            state, self._vx, self._vy, self._omega, distance,
            distance_error, center, yaw_error,
            f"目标距离 {distance} mm，航向差 {yaw_error:+.1f}°",
        )
