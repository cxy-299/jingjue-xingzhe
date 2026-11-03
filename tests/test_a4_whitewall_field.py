"""Two frozen FIELD miss frames plus safety negatives, not a broad OCR benchmark."""
from pathlib import Path
import cv2
import numpy as np
import pytest
from src.detection.a4_digit import A4DigitDetector,CLASS_BASE
from src.web_gui import DashboardState
FIXTURES=Path(__file__).parent/'fixtures/a4_whitewall_20261031'

def image(name):
    frame=cv2.imread(str(FIXTURES/name))
    assert frame is not None
    return frame

@pytest.mark.parametrize('name',['raw_zero.jpg','user_zero.png'])
def test_reported_full_page_zero_on_white_wall_is_single_detection(name):
    d=A4DigitDetector();out=d.detect(image(name))
    assert len(out)==1
    assert out[0].class_id==CLASS_BASE and out[0].source=='a4_digit_template'
    assert out[0].confidence>=.86
    assert len(d.pages)==1 and d.pages[0]['physical_size_verified'] is False
    assert len(d.anchors)==1

@pytest.mark.parametrize('name',['raw_zero.jpg','user_zero.png'])
def test_field_blank_glyph_is_not_a_target(name):
    frame=image(name)
    # Remove the currently visible glyph, not just its dark outline.
    frame[267:373,278:357]=190
    assert not A4DigitDetector().detect(frame)

@pytest.mark.parametrize('name',['raw_zero.jpg','user_zero.png'])
def test_field_one_orientation_mark_missing_rejected(name):
    frame=image(name)
    if name=='raw_zero.jpg':frame[218:234,389:403]=185
    else:frame[217:232,376:390]=185
    assert not A4DigitDetector().detect(frame)

@pytest.mark.parametrize('name',['raw_zero.jpg','user_zero.png'])
def test_field_upside_down_and_bottom_cut_cannot_create_anchor(name):
    frame=image(name)
    assert not A4DigitDetector().detect(cv2.rotate(frame,cv2.ROTATE_180))
    # A complete digit but a cut-off lower page is NOT a full-page initial lock.
    d=A4DigitDetector();assert not d.detect(frame[:390])
    assert not d.anchors

def test_field_full_page_stable_identity_then_blank_clears_confirmation():
    d=A4DigitDetector();s=DashboardState();s.model_classes=d.names
    s.prepare_mission('a4_digit_0')
    for i in range(6):target,_,task,_=s.process_detections(d.detect(image('raw_zero.jpg')),i)
    assert target and task['task_target_confirmed']
    token=task['task_lock_id']
    target,_,task,_=s.process_detections(d.detect(image('user_zero.png')),6)
    assert target and task['task_target_confirmed'] and task['task_lock_id']==token
    blank=np.full((480,640,3),200,np.uint8)
    target,_,task,_=s.process_detections(d.detect(blank),7)
    assert target is None and not task['task_target_confirmed']
    assert s.pending_nav_goal is None

def test_registration_pair_alone_without_side_bottom_edges_never_makes_page():
    frame=np.full((480,640,3),190,np.uint8)
    cv2.rectangle(frame,(240,120),(246,126),(0,0,0),-1)
    cv2.rectangle(frame,(370,120),(376,126),(0,0,0),-1)
    cv2.putText(frame,'0',(275,265),cv2.FONT_HERSHEY_SIMPLEX,2,(0,0,0),5)
    assert not A4DigitDetector().detect(frame)
