"""Saved-frame and synthetic perspective comparison against frozen R17 v3."""
import importlib.util
import json
from pathlib import Path
import sys
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'tests'))
from test_a4_digit import scene
from src.detection.printed_digit import PrintedDigitDetector


def main():
    spec=importlib.util.spec_from_file_location('frozen_v3',ROOT/'output/board/sin12_hdmi_r17_20261101_163807/sources/src/detection/printed_digit.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    old=module.PrintedDigitDetector();new=PrintedDigitDetector();rows=[]
    quads=[[[195,48],[424,89],[394,412],[221,366]],
           [[180,30],[410,105],[385,420],[223,360]],
           [[170,80],[434,43],[383,394],[220,402]]]
    for shape,quad in enumerate(quads):
        for digit in range(10):
            frame=scene(str(digit),quad)
            frame=np.clip(frame.astype(float)*np.linspace(.42,1.,640)[None,:,None]+18,0,255).astype(np.uint8)
            before=old.detect(frame);after=new.detect(frame)
            rows.append(dict(case=f'keystone{shape}-digit{digit}',expected=digit,
                before=[d.class_id-0xA400 for d in before],after=[d.class_id-0xA400 for d in after],
                paper_reads=new.status['paper_assist_reads']))
    dest=ROOT/'output/board/digit_paper_settle_20261101'
    (dest/'perspective_comparison.json').write_text(json.dumps(rows,indent=2))
    print(json.dumps(dict(cases=len(rows),old_correct=sum(r['before']==[r['expected']] for r in rows),
                         new_correct=sum(r['after']==[r['expected']] for r in rows),
                         gained=[r['case'] for r in rows if r['before']!=[r['expected']] and r['after']==[r['expected']]],
                         regressions=[r for r in rows if r['before']==[r['expected']] and r['after']!=[r['expected']]])))


if __name__=='__main__':main()
