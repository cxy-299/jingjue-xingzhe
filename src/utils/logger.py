from pathlib import Path
from datetime import datetime
import csv


class CsvLogger:
    def __init__(self, directory='logs', enabled=True):
        self.enabled = bool(enabled)
        self.file = None
        self.writer = None

        if self.enabled:
            d = Path(directory)
            d.mkdir(parents=True, exist_ok=True)
            path = d / f"vision_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
            self.file = path.open('w', newline='', encoding='utf-8-sig')
            self.writer = csv.writer(self.file)
            self.writer.writerow([
                'timestamp_ms', 'valid', 'class_id', 'class_name', 'confidence',
                'cx', 'cy', 'w', 'h',
                'action', 'vx', 'vy', 'omega',
                'area_ratio', 'center_error', 'distance_error',
            ])

    def write(self, obs, decision=None):
        if not self.writer:
            return

        if decision is None:
            action = ''
            vx = vy = omega = area = center_error = distance_error = ''
        else:
            action = decision.action
            vx = f'{decision.vx:.5f}'
            vy = f'{decision.vy:.5f}'
            omega = f'{decision.omega:.5f}'
            area = f'{decision.area_ratio:.6f}'
            center_error = f'{decision.center_error:.6f}'
            distance_error = f'{decision.distance_error:.6f}'

        self.writer.writerow([
            obs.timestamp_ms,
            int(obs.valid),
            obs.class_id,
            obs.class_name,
            f'{obs.confidence:.4f}',
            obs.cx, obs.cy, obs.w, obs.h,
            action, vx, vy, omega,
            area, center_error, distance_error,
        ])
        self.file.flush()

    def close(self):
        if self.file:
            self.file.close()
            self.file = None
