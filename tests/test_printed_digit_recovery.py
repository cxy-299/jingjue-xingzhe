"""Digit-first CURRENT-frame recognition and persistent original-task identity.

Software tests only: no Pi camera, serial, motor or FPGA programming.
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import pytest
from src.detection.printed_digit import PrintedDigitDetector
from src.detection.factory import create_detector
from src.detection.locked_target import LockedTarget
from src.web_gui import DashboardState
from src.core.messages import Detection
from src.core.a4_targets import CLASS_BASE,NAMES
from src.comm.pid_tuning import parse_pid_status
from src.comm.mission import parse_mission_status

FONT=Path('C:/Windows/Fonts/arial.ttf')
if not FONT.exists():FONT=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')

def glyph(text='0',xy=(320,300),size=160):
    # No paper outline or registration marks, only current upright ink.
    img=Image.new('RGB',(640,480),(235,235,235));draw=ImageDraw.Draw(img)
    font=ImageFont.truetype(str(FONT),size);b=draw.textbbox((0,0),text,font=font)
    draw.text((xy[0]-(b[2]-b[0])/2-b[0],xy[1]-(b[3]-b[1])/2-b[1]),text,font=font,fill='black')
    return cv2.cvtColor(np.array(img),cv2.COLOR_RGB2BGR)

@pytest.mark.parametrize('digit',range(10))
def test_digit_without_page_edges_marks_or_previous_anchor(digit):
    d=PrintedDigitDetector();out=d.detect(glyph(str(digit)))
    assert len(out)==1 and out[0].class_id==CLASS_BASE+digit
    assert out[0].source=='printed_digit_template'
    assert not hasattr(out[0],'a4_metric_height_mm')
    assert d.pages[0]['physical_size_verified'] is False

@pytest.mark.parametrize('fixture',['raw_zero.jpg','user_zero.png','user_near_zero.png',
                                   'user_near_zero_500mm.png','raw_zero_500mm.jpg'])
def test_reported_full_and_near_real_zero_frames(fixture):
    frame=cv2.imread(str(Path(__file__).parent/'fixtures/a4_whitewall_20261031'/fixture))
    out=PrintedDigitDetector().detect(frame)
    assert len(out)==1 and out[0].class_id==CLASS_BASE

@pytest.mark.parametrize('text',['','12','34','A','X','?','--','O'])
def test_blank_non_digit_and_adjacent_multi_digit_not_standalone(text):
    assert not PrintedDigitDetector().detect(glyph(text))

def test_cut_digit_not_falsely_completed_by_old_frame():
    d=PrintedDigitDetector();assert d.detect(glyph('0'))
    assert not d.detect(glyph('0',xy=(320,475)))
    assert not d.detect(np.full((480,640,3),235,np.uint8))

def test_complete_glyph_fills_height_but_has_real_two_pixel_border():
    frame=glyph();ink=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)<100
    ys,xs=np.where(ink);near=frame[ys.min()-2:ys.max()+3,:]
    out=PrintedDigitDetector().detect(near)
    assert len(out)==1 and out[0].class_id==CLASS_BASE
    # Remove actual ink, rather than just its paper, and the digit is invalid.
    assert not PrintedDigitDetector().detect(near[:-5])

def test_stopped_original_task_survives_long_gap_and_reacquires_elsewhere():
    detector=create_detector({'perception':{'backend':'a4_digits'}})
    state=DashboardState();state.model_classes=NAMES;state.prepare_mission('a4_digit_0')
    frame=glyph();blank=np.full_like(frame,235)
    for i in range(6):target,_,task,_=state.process_detections(detector.detect(frame),i,frame)
    assert target and task['task_target_confirmed'];token=task['task_lock_id'];job=task['mission_id']
    for i in range(6,72):
        target,_,task,_=state.process_detections(detector.detect(blank),i,blank)
        assert target is None and not task['task_target_confirmed']
        assert task['task_lock_id']==token and task['mission_id']==job
    moved=glyph('0',xy=(470,220))
    for i in range(72,75):target,_,task,_=state.process_detections(detector.detect(moved),i*.2+80,moved)
    assert target and task['task_target_confirmed']
    assert task['task_lock_id']==token and task['mission_id']==job
    assert state.pending_nav_goal is None

def test_unique_same_number_is_required_no_other_digit_or_duplicate_guess():
    d=PrintedDigitDetector();tracker=LockedTarget();zero=d.detect(glyph())[0]
    tracker.lock(zero,42,0)
    tracker.update([zero],.1);tracker.update([zero],.2)
    other=d.detect(glyph('1'))
    for i in range(3):assert tracker.update(other,2+i) is None
    for i in range(3):assert tracker.update([zero,zero],6+i) is None
    assert tracker.token==42
    for i in range(2):assert tracker.update([zero],10+i*.2) is None
    assert tracker.update([zero],10.4) is zero and tracker.token==42

def test_large_gaps_between_return_hits_do_not_accumulate():
    d=PrintedDigitDetector();z=d.detect(glyph())[0];t=LockedTarget();t.lock(z,42,0)
    assert t.update([],1) is None
    for now in (5,8,11,14):assert t.update([z],now) is None
    assert t.reacquire_hits==1

def test_digit_can_prepare_task_without_complete_paper():
    d=PrintedDigitDetector();frame=glyph();out=d.detect(frame)
    s=DashboardState();s.model_classes=NAMES
    _,rows,_,_=s.process_detections(out,0,frame)
    task=s.prepare_mission('a4_digit_0',detection_id=rows[0]['detection_id'])
    assert task['mission_class_id']==CLASS_BASE and not task['task_target_confirmed']

def test_r14_state_and_capability_are_not_legacy_r12_support():
    assert parse_pid_status('K0E000000040100')['version']==14
    assert parse_pid_status('K0C000000040100')['version']==12
    waiting=parse_mission_status('J1 Q12345678 S10 CA400 K00000004 N0')
    assert waiting['active'] and waiting['state']==16 and waiting['lock_id']==4

def test_r15_search_state_is_reported_without_changing_task_identity():
    assert parse_pid_status('K0F000000040100')['version']==15
    searching=parse_mission_status('J1 Q12345678 S11 CA400 K00000004 N0')
    assert searching['active'] and searching['state']==17 and searching['lock_id']==4
    assert searching['state_name']=='原目标短角度搜索'
