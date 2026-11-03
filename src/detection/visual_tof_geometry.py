"""Offline calibrated geometry prototype; NOT connected to the vehicle controller.

Camera axes: x right, y down, z forward. Positive yaw is left/CCW.
The pinhole size estimate requires the SAME known, upright, fully visible object.
No result here grants movement, identifies a ToF return, or establishes arrival.
An uncalibrated/cropped/low-confidence observation is rejected, not guessed.
"""
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class VisualToFCalibration:
    calibration_id: str
    width: int
    height: int
    fx_px: float
    fy_px: float
    cx_px: float
    cy_px: float
    target_height_mm: float
    tof_x_mm: float
    tof_y_mm: float
    tof_yaw_left_deg: float
    tof_pitch_down_deg: float
    min_range_mm: float
    max_range_mm: float
    tof_z_mm: float = 0.0

    def __post_init__(self):
        if not self.calibration_id.strip():
            raise ValueError('Measured calibration provenance is required')
        values = (self.width, self.height, self.fx_px, self.fy_px, self.cx_px,
                  self.cy_px, self.target_height_mm, self.tof_x_mm, self.tof_y_mm,
                  self.tof_yaw_left_deg, self.tof_pitch_down_deg,
                  self.min_range_mm, self.max_range_mm, self.tof_z_mm)
        if any(isinstance(v, bool) or not math.isfinite(v) for v in values):
            raise ValueError('Calibration must be finite, numeric and not boolean')
        if (type(self.width) is not int or type(self.height) is not int
                or min(self.width, self.height, self.fx_px, self.fy_px,
                       self.target_height_mm, self.min_range_mm) <= 0
                or self.max_range_mm <= self.min_range_mm
                or not 0 <= self.cx_px < self.width
                or not 0 <= self.cy_px < self.height
                or abs(self.tof_yaw_left_deg) >= 45
                or abs(self.tof_pitch_down_deg) >= 45):
            raise ValueError('Calibration is outside the supported geometry')


def estimate_target_geometry(detection, calibration, *, age_ms, confirmed_same_target,
                             full_object_verified=False):
    """Return coarse optical-z and relative yaw only; stale/partial views give None.

    max age300ms matches R12's existing fresh-observation bound, not an extension.
    Ray-inside-box is merely a possible association, NEVER proof of a bottle hit.
    """
    if not isinstance(calibration, VisualToFCalibration):
        raise ValueError('No measured calibration; visual distance is unavailable')
    c = calibration
    # Interior boxes can still describe an occluded bottle. Edge checks alone
    # are not proof that the known physical height is visible.
    if (not full_object_verified or not confirmed_same_target or isinstance(age_ms, bool)
            or not math.isfinite(age_ms) or not 0 <= age_ms < 300):
        return None
    d = detection
    values = (d.x1, d.y1, d.x2, d.y2, d.confidence)
    if any(isinstance(v, bool) or not math.isfinite(v) for v in values):
        return None
    if ((d.frame_width, d.frame_height) != (c.width, c.height)
            or not .50 <= d.confidence <= 1
            or not c.width*.01 < d.x1 < d.x2 < c.width*.99
            or not c.height*.01 < d.y1 < d.y2 < c.height*.99):
        return None
    z = c.fy_px*c.target_height_mm/d.h_px
    if not c.min_range_mm <= z <= c.max_range_mm:
        return None
    dz = z-c.tof_z_mm
    if dz <= 0:
        return None
    beam_x_norm = (c.tof_x_mm-dz*math.tan(math.radians(c.tof_yaw_left_deg)))/z
    beam_y_norm = (c.tof_y_mm+dz*math.tan(math.radians(c.tof_pitch_down_deg)))/z
    beam_x = c.cx_px+c.fx_px*beam_x_norm
    beam_y = c.cy_px+c.fy_px*beam_y_norm
    target_right = math.atan((d.cx_px-c.cx_px)/c.fx_px)
    yaw_left = math.degrees(math.atan(beam_x_norm)-target_right)
    return dict(calibration_id=c.calibration_id, coarse_optical_z_mm=z,
                yaw_left_deg=yaw_left, beam_pixel=(beam_x, beam_y),
                ray_inside_box=d.x1 < beam_x < d.x2 and d.y1 < beam_y < d.y2,
                distance_authoritative=False, motion_authorized=False,
                scope='offline prototype; size/depth/beam association not field validated')
