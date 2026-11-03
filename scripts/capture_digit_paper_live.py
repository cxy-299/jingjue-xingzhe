"""Read-only paired raw snapshots/metadata and stopped-state observations."""
import base64
import argparse
from datetime import datetime
import json
from pathlib import Path
import statistics
import time
import urllib.request

BASE=Path(__file__).resolve().parents[1]/'output/board/digit_paper_settle_20261101'
HTTP=urllib.request.build_opener(urllib.request.ProxyHandler({}))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--tag',default='live_card')
    parser.add_argument('--revision',default='printed-digit-v4-paper-assist-bounded-20261101')
    args=parser.parse_args();assert args.tag and all(c.isalnum() or c=='_' for c in args.tag)
    OUT=BASE/args.tag
    OUT.mkdir(exist_ok=True);rows=[];seen=set();deadline=time.monotonic()+30
    while len(rows)<25 and time.monotonic()<deadline:
        with HTTP.open('http://192.168.137.129:8080/api/status',timeout=4) as r:s=json.load(r)
        assert s.get('detector_revision')==args.revision
        assert not s.get('mission_fpga',{}).get('active') and s.get('task_mode')=='observe'
        assert not s.get('nav_goal_pending') and s.get('motion_commands_enabled') is False
        if s['frame_id'] in seen:time.sleep(.1);continue
        seen.add(s['frame_id']);rows.append(s)
        if len(rows) in (1,13,25):
            with HTTP.open('http://192.168.137.129:8080/snapshot-raw.jpg',timeout=4) as r:
                (OUT/f'raw_{len(rows):02}.jpg').write_bytes(r.read())
                meta=json.loads(base64.b64decode(r.headers['X-Vision-Metadata']))
                (OUT/f'raw_{len(rows):02}.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
        time.sleep(.2)
    result=dict(collected_at_windows_local=datetime.now().astimezone().isoformat(),frames=rows,frame_count=len(rows),
                detected_frames=sum(s.get('detection_count',0)>0 for s in rows),
                fps_median=statistics.median(s['fps'] for s in rows),
                detector_ms_median=statistics.median(s['detector_ms'] for s in rows),
                identity_counts={str(n):sum(any(d.get('class_id')==n for d in s['detections']) for s in rows)
                                 for n in range(0xA400,0xA40A)})
    (OUT/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in result.items() if k!='frames'},ensure_ascii=False))


if __name__=='__main__':main()
