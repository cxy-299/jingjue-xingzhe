"""Offline model/fixture check on the Pi. Never opens camera/serial or sends HTTP POST."""
import argparse
import json
from pathlib import Path
import statistics
import sys
import time


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--stage',required=True)
    ap.add_argument('--model',required=True)
    args=ap.parse_args()
    stage=Path(args.stage).resolve()
    sys.path.insert(0,str(stage))
    import cv2
    from src.detection.yolo_detector import YOLODetector
    detector=YOLODetector(args.model,.45,.50,416,'cpu')
    records=[]
    for name in ('snapshot','user_miss','user_vase_annotated'):
        frame=cv2.imread(str(stage/f'{name}_model_input.jpg'))
        assert frame is not None
        baseline=detector._predict(frame,0)
        detector._near_remaining=0;detector._frame_number=3
        actual=detector.detect(frame)
        row=dict(fixture=name,annotated_fixture=name=='user_vase_annotated',
            baseline=[dict(name=d.class_name,confidence=d.confidence) for d in baseline],
            revised=[dict(name=d.class_name,confidence=d.confidence,source=d.source,
                          box=[d.x1,d.y1,d.x2,d.y2]) for d in actual],status=detector.status.copy())
        assert any(d.class_name=='bottle' and d.confidence>=.75 for d in actual),row
        records.append(row)
    # Real Pi warm single-pass runtime, with the live service still running.
    frame=cv2.imread(str(stage/'snapshot_model_input.jpg'));latencies=[]
    for _ in range(6):
        ts=time.monotonic();actual=detector.detect(frame);latencies.append(time.monotonic()-ts)
        assert detector.status['detector_passes']==1
        assert any(d.class_name=='bottle' for d in actual)
    report=dict(passed=True,hardware_commands=False,camera_opened=False,serial_opened=False,
                records=records,pi_warm_seconds=latencies,median_seconds=statistics.median(latencies),
                note='Offline fixture inference, competing with live service. Not a new physical task pass.')
    (stage/'pi_model_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False),flush=True)


if __name__=='__main__':main()
