"""Pi-native file-only candidate checks; never open camera/serial or restart service."""
from pathlib import Path
import json,time,hashlib,sys
import cv2
import numpy as np
from src.detection.printed_digit import PrintedDigitDetector
from src.web_gui import DashboardState
from src.core.a4_targets import CLASS_BASE,NAMES
ROOT=Path(__file__).resolve().parents[1]
def main():
    detector=PrintedDigitDetector();results=[]
    for name in ('raw_zero.jpg','user_zero.png','user_near_zero.png','raw_zero_500mm.jpg','user_near_zero_500mm.png'):
        frame=cv2.imread(str(ROOT/'tests/fixtures/a4_whitewall_20261031'/name));assert frame is not None,name
        begin=time.monotonic();out=detector.detect(frame);ms=(time.monotonic()-begin)*1000
        assert len(out)==1 and out[0].class_id==CLASS_BASE,(name,out)
        results.append(dict(file=name,class_id=out[0].class_id,score=out[0].confidence,elapsed_ms=round(ms,2)))
    state=DashboardState();state.model_classes=NAMES;state.prepare_mission('a4_digit_0')
    frame=cv2.imread(str(ROOT/'tests/fixtures/a4_whitewall_20261031/raw_zero_500mm.jpg'))
    for i in range(6):target,_,task,_=state.process_detections(detector.detect(frame),i*.1,frame)
    assert target and task['task_target_confirmed'];job=task['mission_id'];token=task['task_lock_id']
    blank=np.full_like(frame,235)
    for i in range(1,67):
        target,_,task,_=state.process_detections([],i,blank)
        assert target is None and not task['task_target_confirmed'] and task['mission_id']==job and task['task_lock_id']==token
    for i in range(3):target,_,task,_=state.process_detections(detector.detect(frame),67+i*.2,frame)
    assert target and task['task_target_confirmed'] and task['mission_id']==job and task['task_lock_id']==token
    assert state.pending_nav_goal is None
    # Entire current glyph is required. Cutting this real zero must revoke it.
    assert not detector.detect(frame[:440])
    assert not detector.detect(blank)
    samples=[]
    for i in range(20):
        begin=time.monotonic();out=detector.detect(frame);samples.append((time.monotonic()-begin)*1000)
        assert len(out)==1 and out[0].class_id==CLASS_BASE
    report=dict(hardware_access=False,service_modified=False,python=sys.version.split()[0],opencv=cv2.__version__,numpy=np.__version__,
        detector_revision=detector.revision,fixtures=results,long_gap_seconds=66,same_job_token_resumed=True,
        raw_frame_mean_ms=round(sum(samples)/len(samples),2),raw_frame_max_ms=round(max(samples),2),
        limits='file-only native inference; not live FPS, movement, end-to-end or arbitrary-font OCR signoff')
    print(json.dumps(report,ensure_ascii=False,indent=2));return 0
if __name__=='__main__':raise SystemExit(main())
