from dataclasses import dataclass
from typing import Optional

@dataclass
class Detection:
    class_id: int
    class_name: str
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float
    frame_width: int
    frame_height: int
    source: str = 'model'

    @property
    def cx_px(self): return (self.x1 + self.x2) / 2
    @property
    def cy_px(self): return (self.y1 + self.y2) / 2
    @property
    def w_px(self): return max(0.0, self.x2 - self.x1)
    @property
    def h_px(self): return max(0.0, self.y2 - self.y1)
    @property
    def area_ratio(self): return self.w_px * self.h_px / max(1, self.frame_width * self.frame_height)

    def normalized_10000(self):
        def norm(v, total):
            return max(0, min(10000, int(round(v / max(1, total) * 10000))))
        return {
            'cx': norm(self.cx_px, self.frame_width),
            'cy': norm(self.cy_px, self.frame_height),
            'w': norm(self.w_px, self.frame_width),
            'h': norm(self.h_px, self.frame_height),
        }

@dataclass
class TargetObservation:
    timestamp_ms: int
    valid: bool
    class_id: int = 0xFFFF
    class_name: str = ''
    confidence: float = 0.0
    cx: int = 0
    cy: int = 0
    w: int = 0
    h: int = 0

    @classmethod
    def from_detection(cls, timestamp_ms: int, det: Optional[Detection]):
        if det is None:
            return cls(timestamp_ms=timestamp_ms, valid=False)
        n = det.normalized_10000()
        return cls(timestamp_ms, True, det.class_id, det.class_name, det.confidence,
                   n['cx'], n['cy'], n['w'], n['h'])
