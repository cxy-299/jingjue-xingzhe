"""Current-frame robustness only, no motor/Pi service access or cached glyphs."""
from pathlib import Path
import cv2
import numpy as np
import pytest
from src.core.a4_targets import CLASS_BASE
from src.detection.printed_digit import PrintedDigitDetector

FIELD=Path(__file__).resolve().parents[1]/'output/board/r17_digit_card_raw_20261101.jpg'

def field():
    frame=cv2.imread(str(FIELD))
    assert frame is not None
    return frame

@pytest.mark.parametrize('angle',[-12,-8,-4,0,4,8,12])
def test_field_zero_mild_camera_roll(angle):
    frame=field();h,w=frame.shape[:2]
    image=cv2.warpAffine(frame,cv2.getRotationMatrix2D((w/2,h/2),angle,1),
                         (w,h),borderMode=cv2.BORDER_REFLECT_101)
    out=PrintedDigitDetector().detect(image)
    assert len(out)==1 and out[0].class_id==CLASS_BASE

@pytest.mark.parametrize('gain,offset',[(1.,0),(.55,70),(.35,25),(.3,150)])
def test_field_zero_exposure_changes(gain,offset):
    image=np.clip(field().astype(float)*gain+offset,0,255).astype(np.uint8)
    out=PrintedDigitDetector().detect(image)
    assert len(out)==1 and out[0].class_id==CLASS_BASE

@pytest.mark.parametrize('kernel',[3,5])
def test_field_zero_small_defocus(kernel):
    out=PrintedDigitDetector().detect(cv2.GaussianBlur(field(),(kernel,kernel),0))
    assert len(out)==1 and out[0].class_id==CLASS_BASE

def test_current_blank_cannot_reuse_previous_readable_card():
    detector=PrintedDigitDetector();assert detector.detect(field())
    assert not detector.detect(np.full_like(field(),230))

def test_current_wrong_requested_class_cannot_relabel_zero():
    out=PrintedDigitDetector().detect(field(),target_class=CLASS_BASE+8)
    assert len(out)==1 and out[0].class_id==CLASS_BASE
