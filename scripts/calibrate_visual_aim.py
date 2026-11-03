"""Produce a fixed aim suggestion from MANUALLY verified ToF beam points.

Input JSON: {width, height, distance_mm, points: [[x_px,y_px], ...]}.
At one reference distance, locate the ToF response centre with a narrow opaque
target against a distant background and mark its position in raw camera images.
This tool does not infer beam position from detector boxes or ToF range alone.
It writes a report; never edits running config or sends vehicle commands.
"""
import argparse
import json
import math
from pathlib import Path
import statistics


def suggest_aim(samples):
    width, height, distance = (float(samples[k]) for k in ('width', 'height', 'distance_mm'))
    if not all(math.isfinite(v) and v > 0 for v in (width, height, distance)):
        raise ValueError('Resolution and manually measured distance must be positive')
    points = samples['points']
    if len(points) < 3:
        raise ValueError('Need at least three independently positioned beam checks')
    if any(len(p) != 2 or not all(math.isfinite(float(v)) for v in p)
           or not 0 <= float(p[0]) < width or not 0 <= float(p[1]) < height for p in points):
        raise ValueError('Beam point is outside the raw camera image')
    xs, ys = [float(p[0]) for p in points], [float(p[1]) for p in points]
    # Reject inconsistent manual checks rather than quietly averaging them.
    if max(xs)-min(xs) > width*.04 or max(ys)-min(ys) > height*.04:
        raise ValueError('Beam checks disagree by over 4% of the image; repeat calibration')
    return dict(reference_distance_mm=distance, sample_count=len(points),
        suggested_visual_alignment=dict(center_target=round(statistics.median(xs)/width*10000),
                                        aim_y_target=round(statistics.median(ys)/height*10000)),
        automatic_application=False,
        scope='Fixed reference at this distance only; vertical value is a guide, not height control',
        far_near_verification_required=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('samples', type=Path)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    report = suggest_aim(json.loads(a.samples.read_text(encoding='utf8')))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
