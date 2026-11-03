"""Perception-only task preparation; the FPGA owns motion and task completion."""
import secrets

from src.detection.locked_target import LockedTarget
from src.detection.red_bottle import red_coverage
from src.core.a4_targets import is_a4_category


class SemanticMission:
    def __init__(self):
        self.task_id = 0
        self.category = ''
        self.color = 'any'
        self.distance_mm = 200
        self.candidate = None
        self.hits = 0
        self.last_at = None

    def prepare(self, category, color='any', distance_mm=200):
        if not isinstance(category, str) or not category.strip() or len(category) > 32:
            raise ValueError('请填写模型支持的类别，例如 bottle/person/cat/tv')
        if color not in ('any', 'red'):
            raise ValueError('颜色只支持 any/red')
        if is_a4_category(category) and color != 'any':
            raise ValueError('A4数字任务按数字身份匹配，不使用红色筛选')
        if type(distance_mm) is not int or not 180 <= distance_mm <= 1000:
            raise ValueError('到达距离须为180–1000毫米的整数')
        self.task_id = secrets.randbelow(0xffffffff) + 1
        self.category, self.color, self.distance_mm = category.strip(), color, distance_mm
        self.candidate, self.hits, self.last_at = None, 0, None

    def clear(self):
        self.task_id = 0
        self.candidate, self.hits, self.last_at = None, 0, None

    def candidate_for(self, detections, frame, now):
        """Three consecutive unambiguous observations before automatic identity lock.

        Multiple matching objects require a manual choice, not largest-box guessing.
        Red means >=15% of the inner box; this is not proof the whole object is red.
        """
        candidates = [d for d in detections if d.class_name == self.category
                      and d.confidence >= .50
                      and (not is_a4_category(self.category) or d.source in ('a4_digit_template','printed_digit_template'))
                      and (self.color == 'any' or (frame is not None
                           and red_coverage(frame, d) >= .15))]
        if len(candidates) != 1:
            self.candidate, self.hits, self.last_at = None, 0, None
            return None, '多个候选，请减少同类干扰后重新准备任务' if candidates else '等待符合类别/颜色的目标'
        current = candidates[0]
        continuous = (self.candidate is not None and self.last_at is not None
                      and now-self.last_at <= 1.2
                      and LockedTarget.score(self.candidate, current) is not None)
        self.hits = self.hits+1 if continuous else 1
        self.candidate, self.last_at = current, now
        return (current if self.hits >= 3 else None), f'语义目标连续确认 {self.hits}/3 帧'

    def snapshot(self):
        return dict(mission_id=self.task_id, mission_class=self.category,
                    mission_color=self.color, mission_distance_mm=self.distance_mm)
