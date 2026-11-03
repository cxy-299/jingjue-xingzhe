from src.detection.red_bottle import red_coverage


class TargetSelector:
    def __init__(self, class_names=None, selection='largest',
                 min_area_ratio=0.0, red_bottle=None):
        self.class_names = set(class_names or [])
        self.selection = selection
        self.min_area_ratio = float(min_area_ratio)
        color_cfg = red_bottle or {}
        self.require_red = bool(color_cfg.get('enabled', False))
        self.min_red_ratio = float(color_cfg.get('min_red_ratio', 0.12))
        self.red_ratios = {}

    def choose(self, detections, frame_bgr=None):
        """先按类别/尺寸筛选；开启红色筛选时再检查原始 BGR 图像。

        无图像时安全地返回无目标，不能把普通瓶子误发给 FPGA 当作红瓶。
        """
        candidates = []
        self.red_ratios = {}
        for detection in detections:
            if self.class_names and detection.class_name not in self.class_names:
                continue
            if detection.area_ratio < self.min_area_ratio:
                continue
            if self.require_red:
                if frame_bgr is None:
                    continue
                ratio = red_coverage(frame_bgr, detection)
                self.red_ratios[id(detection)] = ratio
                if ratio < self.min_red_ratio:
                    continue
            candidates.append(detection)

        if not candidates:
            return None
        if self.selection == 'confidence':
            return max(candidates, key=lambda d: d.confidence)
        if self.selection == 'center':
            return min(candidates, key=lambda d:
                       (d.cx_px / max(1, d.frame_width) - 0.5) ** 2 +
                       (d.cy_px / max(1, d.frame_height) - 0.5) ** 2)
        return max(candidates, key=lambda d: d.area_ratio)
