"""Experimental perception-only geometry. Never commands motion or reports arrival.

An interior bbox is NOT proof of full visibility. Size is only an advisory known-
height/upright-object assumption with an explicit wide uncertainty. FPGA must
cross-check fresh ToF and retain its independent live safety path.
"""
import json
import math
from pathlib import Path
from src.detection.visual_tof_geometry import VisualToFCalibration


class MissionGeometryReporter:
    def __init__(self, calibration, *, uncertainty_fraction=.40, target_class="bottle", capture_age_bound_ms=0):
        if not isinstance(calibration, VisualToFCalibration):
            raise ValueError('Measured camera/ToF calibration is required')
        if not .25 <= uncertainty_fraction <= .5:
            raise ValueError('Advisory size uncertainty must be 25–50 percent')
        if not isinstance(target_class,str) or not target_class.strip():
            raise ValueError("Calibration must name its target class")
        if type(capture_age_bound_ms) is not int or not 0<=capture_age_bound_ms<280:
            raise ValueError("A measured capture queue age bound is required")
        self.capture_age_bound_ms = capture_age_bound_ms
        self.target_class = target_class
        self.calibration = calibration
        self.uncertainty_fraction = uncertainty_fraction

    @classmethod
    def from_config(cls, cfg):
        settings = cfg.get('mission_geometry', {})
        if not settings.get('enabled', False):
            return None
        # No synthetic/fallback focal length, target height or 3mm->pixel guess.
        path = settings.get('calibration_file')
        if not path:
            raise ValueError('mission_geometry requires a measured calibration_file')
        document = json.loads(Path(path).read_text(encoding='utf-8'))
        if document.get('field_verified') is not True:
            raise ValueError('Calibration must be field_verified before enabling geometry')
        if 'tof_z_mm' not in document['calibration']:
            raise ValueError('Measure forward ToF/camera offset too; do not assume it is zero')
        return cls(VisualToFCalibration(**document['calibration']),
                   uncertainty_fraction=settings.get('uncertainty_fraction', .40),
                   target_class=document['target_class'],
                   capture_age_bound_ms=document['capture_age_bound_ms'])

    def observe(self, detection, *, age_ms, confirmed):
        c, d = self.calibration, detection
        # A visible digit bbox is NOT a 297mm paper bbox. Never turn the old
        # full-page height or cached range into a fresh partial-page estimate.
        if d is not None and d.source in ('a4_partial_digit','printed_digit_template'):
            return None
        if isinstance(age_ms,bool) or not math.isfinite(age_ms) or age_ms<0:
            return None
        age_ms += self.capture_age_bound_ms
        if (d is None or d.class_name!=self.target_class or not confirmed
                or isinstance(age_ms,bool) or not math.isfinite(age_ms) or not 0 <= age_ms < 280):
            return None
        vals = (d.x1,d.x2,d.y1,d.y2,d.confidence)
        if any(isinstance(v,bool) or not math.isfinite(v) for v in vals):
            return None
        if ((d.frame_width,d.frame_height)!=(c.width,c.height) or not .5<=d.confidence<=1
                or not c.width*.01<d.x1<d.x2<c.width*.99
                or not c.height*.01<d.y1<d.y2<c.height*.99):
            return None
        z = c.fy_px*c.target_height_mm/d.h_px
        if not max(150,c.min_range_mm)<=z<=min(c.max_range_mm,10000):
            return None
        dz = z-c.tof_z_mm
        if dz<=0:
            return None
        ray_mm = dz/(math.cos(math.radians(c.tof_yaw_left_deg))*math.cos(math.radians(c.tof_pitch_down_deg)))
        if not max(150,c.min_range_mm)<=ray_mm<=min(c.max_range_mm,10000):
            return None
        beam_x = c.cx_px+c.fx_px*(c.tof_x_mm-dz*math.tan(math.radians(c.tof_yaw_left_deg)))/z
        beam_y = c.cy_px+c.fy_px*(c.tof_y_mm+dz*math.tan(math.radians(c.tof_pitch_down_deg)))/z
        yaw = math.degrees(math.atan((beam_x-c.cx_px)/c.fx_px)
                           - math.atan((d.cx_px-c.cx_px)/c.fx_px))
        if not -45<=yaw<=45:
            return None
        # Known-height assumption is explicit, not a claim of occlusion detection.
        return dict(yaw_left_cdeg=round(yaw*100), coarse_mm=round(ray_mm),
                    uncertainty_mm=min(round(ray_mm)//2,max(20,math.ceil(ray_mm*self.uncertainty_fraction))),
                    coarse_optical_z_mm=z,
                    beam_inside=d.x1<beam_x<d.x2 and d.y1<beam_y<d.y2,
                    observation_age_ms=math.ceil(age_ms), calibration_id=c.calibration_id,
                    visibility_verified=False, distance_authoritative=False,
                    range_basis='known-height upright bbox assumption; ToF cross-check required')

