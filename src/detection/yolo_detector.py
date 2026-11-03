"""Native YOLO detections, with bounded context padding for clipped bottles.

Padding changes input framing, not semantic labels. Every returned box still
comes from this frame's model inference; no missing-frame or vase relabelling.
"""
from src.core.messages import Detection

class YOLODetector:
    def __init__(self, model_path, conf_threshold=0.45, iou_threshold=0.5, imgsz=640, device='cpu', near_bottle=None):
        from ultralytics import YOLO
        self.model = YOLO(model_path)
        self.conf, self.iou, self.imgsz, self.device = float(conf_threshold), float(iou_threshold), int(imgsz), device
        cfg = near_bottle or {}
        self.near_enabled = bool(cfg.get('enabled', True))
        self.near_margin = max(.1, min(.5, float(cfg.get('margin', .30))))
        self._near_remaining = 0
        self._frame_number = 0
        self._misses = 0
        self.status = {}

    @property
    def names(self):
        return self.model.names

    @property
    def label(self):
        return str(self.model.ckpt_path) if getattr(self.model, "ckpt_path", None) else "YOLO"

    def _predict(self, frame_bgr, margin=0):
        import cv2
        h,w = frame_bgr.shape[:2]
        border = round(max(h, w) * margin)
        source = (cv2.copyMakeBorder(frame_bgr, border, border, border, border,
                                    cv2.BORDER_CONSTANT, value=(114, 114, 114))
                  if border else frame_bgr)
        results = self.model.predict(source=source, conf=self.conf, iou=self.iou,
                                     imgsz=self.imgsz, device=self.device, verbose=False)
        out=[]
        if not results or results[0].boxes is None: return out
        r=results[0]
        for box in r.boxes:
            x1,y1,x2,y2 = box.xyxy[0].tolist()
            # Model boxes are in padded source coordinates. Clip back to the
            # actual camera, never use padded dimensions for centre/area/UART.
            x1,y1 = max(0., min(w, x1-border)), max(0., min(h, y1-border))
            x2,y2 = max(0., min(w, x2-border)), max(0., min(h, y2-border))
            if x2-x1 < 4 or y2-y1 < 4:
                continue
            cid=int(box.cls[0].item()); conf=float(box.conf[0].item())
            name=str(r.names.get(cid,cid))
            out.append(Detection(cid,name,conf,x1,y1,x2,y2,w,h,
                                 'near_context' if border else 'model'))
        return out

    @staticmethod
    def _near(d):
        return (d.class_name in ('bottle', 'vase') and d.area_ratio >= .12
                and d.h_px >= d.frame_height*.65
                and (d.y1 <= d.frame_height*.04 or d.y2 >= d.frame_height*.96))

    @staticmethod
    def _overlap(a, b):
        area = max(0, min(a.x2,b.x2)-max(a.x1,b.x1))*max(0,min(a.y2,b.y2)-max(a.y1,b.y1))
        return area/max(1, a.w_px*a.h_px+b.w_px*b.h_px-area)

    def detect(self, frame_bgr, target_class=None):
        import time
        started = time.monotonic()
        self._frame_number += 1
        enabled = self.near_enabled and target_class in (None, '', 'bottle')
        margin = self.near_margin if enabled and self._near_remaining else 0
        out = self._predict(frame_bgr, margin)
        calls = 1
        bottles = [d for d in out if d.class_name == 'bottle']
        if enabled and not margin and (
                any(self._near(d) for d in out) or
                (not bottles and self._frame_number % 4 == 0)):
            # At most one extra pass, only on entry or periodic discovery.
            # Once close, padding is the SINGLE main pass at the same imgsz.
            alternate = self._predict(frame_bgr, self.near_margin)
            calls += 1
            recovered = [d for d in alternate if d.class_name == 'bottle' and self._near(d)]
            if recovered:
                out = [d for d in out if not (d.class_name in ('bottle','vase')
                       and any(self._overlap(d,b) >= .40 for b in recovered))] + recovered
                margin = self.near_margin
        elif enabled and margin and not bottles and self._misses % 3 == 2:
            alternate = self._predict(frame_bgr, .50)
            calls += 1
            recovered = [d for d in alternate if d.class_name == 'bottle' and self._near(d)]
            if recovered:
                out = [d for d in out if not (d.class_name in ('bottle','vase')
                       and any(self._overlap(d,b) >= .40 for b in recovered))] + recovered
                margin = .50
        near_bottles = [d for d in out if d.class_name == 'bottle' and self._near(d)]
        self._near_remaining = (6 if near_bottles else max(0,self._near_remaining-1)) if enabled else 0
        self._misses = 0 if any(d.class_name=='bottle' for d in out) else self._misses+1
        self.status = dict(near_bottle_mode=bool(margin), detector_context_margin=margin,
                           detector_passes=calls, detector_ms=round((time.monotonic()-started)*1000,1),
                           detector_revision='near-bottle-v1-20261030')
        return out
