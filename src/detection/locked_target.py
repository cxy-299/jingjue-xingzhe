"""Persistent selected-object lock with conservative appearance reacquisition.

The token/category survive missing detections. Appearance and two consecutive
observations can restore visibility; ambiguity never picks the largest object.
This lightweight color descriptor is not a person identity recognition model.
"""
import math


class LockedTarget:
    def __init__(self):
        self.clear()

    def clear(self):
        self.detection = None
        self.token = 0
        self.last_seen = 0.0
        self.missing = False
        self.ambiguous = False
        self.hits = 0
        self.reference_appearance = None
        self.reacquire_detection = None
        self.reacquire_hits = 0
        self.reacquired = False
        self.appearance_gallery = []
        self.match_reason = 'not_selected'
        self.candidate_count = 0
        self.best_distance = None
        self.reacquire_required = 2
        self.reacquire_at = None

    def lock(self, detection, token, now, appearance=None):
        self.clear()
        self.detection = detection
        self.token = token
        self.last_seen = now
        self.missing = self.ambiguous = False
        self.hits = 0
        self.reference_appearance = appearance
        self.appearance_gallery = [appearance] if appearance is not None else []
        self.match_reason = 'confirming'

    @staticmethod
    def appearance(frame, detection):
        """Fixed-size HSV histogram of the inner crop; no image retained."""
        if frame is None:
            return None
        import cv2
        height, width = frame.shape[:2]
        dx, dy = detection.w_px * .08, detection.h_px * .08
        x1, y1 = max(0, int(detection.x1+dx)), max(0, int(detection.y1+dy))
        x2, y2 = min(width, int(detection.x2-dx)), min(height, int(detection.y2-dy))
        if x2-x1 < 4 or y2-y1 < 4:
            return None
        crop = cv2.resize(frame[y1:y2, x1:x2], (48, 64))
        hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        # Coarse, smoothed HS bins tolerate shading and small hue shifts. Hue
        # wraps around (red at both ends); value is deliberately excluded.
        import numpy as np
        hist = cv2.calcHist([hsv], [0, 1], None, [12, 8], [0, 180, 0, 256])
        hist = (np.roll(hist, 1, axis=0) + 2*hist + np.roll(hist, -1, axis=0))/4
        padded = np.pad(hist, ((0,0),(1,1)), mode='edge')
        hist = (padded[:,:-2] + 2*padded[:,1:-1] + padded[:,2:])/4
        return hist / max(1., float(hist.sum()))

    @staticmethod
    def appearance_distance(first, second):
        if first is None or second is None:
            return None
        import cv2
        return float(cv2.compareHist(first, second, cv2.HISTCMP_BHATTACHARYYA))

    @staticmethod
    def score(a, b):
        if a.class_id != b.class_id:
            return None
        # A4 full-page -> partial-page transition compares the CURRENT printed
        # glyph on both frames, not a full paper box against a small digit box.
        sources = ('a4_digit_template', 'a4_partial_digit', 'printed_digit_template')
        glyphs = (getattr(a, 'a4_glyph_bbox', None), getattr(b, 'a4_glyph_bbox', None))
        if a.source in sources and b.source in sources and all(glyphs):
            ax, ay, aw, ah = glyphs[0]
            bx, by, bw, bh = glyphs[1]
        else:
            ax, ay, aw, ah = a.x1, a.y1, a.w_px, a.h_px
            bx, by, bw, bh = b.x1, b.y1, b.w_px, b.h_px
        inter = max(0, min(ax+aw, bx+bw)-max(ax, bx)) * max(0, min(ay+ah, by+bh)-max(ay, by))
        aa, ab = aw*ah, bw*bh
        iou = inter / max(1, aa + ab - inter)
        dist = math.hypot((ax+aw/2-bx-bw/2)/max(1,a.frame_width),
                          (ay+ah/2-by-bh/2)/max(1,a.frame_height))
        ratio = ab / max(1, aa)
        if not 0.4 <= ratio <= 2.5 or (iou < 0.12 and dist > 0.12):
            return None
        return iou - dist

    def distance(self, appearance):
        distances = [self.appearance_distance(item, appearance)
                     for item in self.appearance_gallery]
        distances = [value for value in distances if value is not None]
        return min(distances) if distances else None

    def remember(self, appearance):
        if appearance is None:
            return
        # Keep the clicked anchor plus three recent, unambiguously tracked views.
        if self.distance(appearance) is None or self.distance(appearance) > .08:
            self.appearance_gallery.append(appearance)
            if len(self.appearance_gallery) > 4:
                self.appearance_gallery = self.appearance_gallery[:1] + self.appearance_gallery[-3:]

    def update_printed_digit(self,detections,now):
        """Unique CURRENT same printed number, not white-paper appearance.

        Retain token indefinitely without claiming visibility. After a miss,
        search the full frame and require THREE consecutive readable matches;
        never choose between duplicate-number cards or accept a different digit.
        """
        same=[d for d in detections if d.class_id==self.detection.class_id
              and d.source=='printed_digit_template' and d.confidence>=.86]
        self.candidate_count=len(same);self.best_distance=None
        if len(same)!=1:
            self.missing=True;self.hits=0;self.ambiguous=len(same)>1
            self.reacquire_detection=None;self.reacquire_hits=0;self.reacquire_at=None
            self.match_reason='ambiguous' if self.ambiguous else 'not_visible'
            return None
        candidate=same[0]
        if now-self.last_seen>1.2:self.missing=True;self.hits=0
        if not self.missing and self.score(self.detection,candidate) is not None:
            self.detection=candidate;self.last_seen=now;self.hits+=1
            self.ambiguous=False;self.match_reason='tracking'
            return candidate
        self.missing=True;self.hits=0;self.reacquire_required=3
        continuous=(self.reacquire_detection is not None and self.reacquire_at is not None
                    and 0<=now-self.reacquire_at<=1.2
                    and self.score(self.reacquire_detection,candidate) is not None)
        self.reacquire_hits=self.reacquire_hits+1 if continuous else 1
        self.reacquire_detection=candidate;self.reacquire_at=now
        self.ambiguous=False;self.match_reason='confirming'
        if self.reacquire_hits<self.reacquire_required:return None
        self.detection=candidate;self.last_seen=now;self.hits=3;self.missing=False
        self.reacquired=True;self.match_reason='reacquired'
        self.reacquire_detection=None;self.reacquire_hits=0;self.reacquire_at=None
        return candidate

    def update(self, detections, now, appearances=None):
        self.reacquired = False
        if self.detection is None:
            return None
        if self.detection.source=='printed_digit_template':
            return self.update_printed_digit(detections,now)
        appearances = appearances or [None] * len(detections)
        self.candidate_count = sum(d.class_id == self.detection.class_id for d in detections)
        self.best_distance = None
        if now - self.last_seen > 1.2:
            self.missing = True
        if not self.missing:
            candidates = []
            for d, appearance in zip(detections, appearances):
                score = self.score(self.detection, d)
                distance = self.distance(appearance)
                if score is not None and (distance is None or distance <= .65):
                    candidates.append((score - .25*(distance or 0), d, appearance))
            candidates.sort(key=lambda item: item[0], reverse=True)
            if candidates and not (len(candidates) > 1 and candidates[0][0]-candidates[1][0] < .10):
                self.detection = candidates[0][1]
                self.last_seen = now
                self.hits += 1
                self.ambiguous = False
                self.match_reason = 'tracking'
                self.remember(candidates[0][2])
                return self.detection
            self.missing = True
            self.ambiguous = len(candidates) > 1
            self.hits = 0

        # Search the full image, retaining the original class and lock token.
        # Without an appearance reference, only the old geometric neighborhood
        # is eligible; a sole same-class object elsewhere is not enough.
        candidates = []
        for d, appearance in zip(detections, appearances):
            if d.class_id != self.detection.class_id:
                continue
            distance = self.distance(appearance)
            ratio = (d.w_px*d.h_px) / max(1, self.detection.w_px*self.detection.h_px)
            if distance is not None:
                self.best_distance = distance if self.best_distance is None else min(self.best_distance, distance)
            if self.reference_appearance is not None:
                # Partial/full person boxes may differ by far more than 5x.
                # A weaker, unique appearance match requires three frames.
                if distance is not None and distance <= .68 and .04 <= ratio <= 25:
                    candidates.append((distance, d, appearance))
            else:
                score = self.score(self.detection, d)
                if score is not None:
                    candidates.append((-score, d, appearance))
        candidates.sort(key=lambda item: item[0])
        if not candidates or (len(candidates) > 1 and candidates[1][0]-candidates[0][0] < .08):
            self.reacquire_detection = None
            self.reacquire_hits = 0
            self.ambiguous = len(candidates) > 1
            self.match_reason = ('ambiguous' if self.ambiguous else
                                 'appearance' if self.candidate_count else 'not_visible')
            return None
        candidate = candidates[0][1]
        self.reacquire_required = 3 if self.reference_appearance is not None and candidates[0][0] > .40 else 2
        continuous = (self.reacquire_detection is not None
                      and self.score(self.reacquire_detection, candidate) is not None)
        self.reacquire_hits = self.reacquire_hits + 1 if continuous else 1
        self.reacquire_detection = candidate
        self.ambiguous = False
        self.match_reason = 'confirming'
        if self.reacquire_hits < self.reacquire_required:
            return None
        self.detection = candidate
        self.last_seen = now
        self.hits = 2
        self.missing = False
        self.reacquired = True
        self.match_reason = 'reacquired'
        self.remember(candidates[0][2])
        self.reacquire_detection = None
        self.reacquire_hits = 0
        return self.detection
