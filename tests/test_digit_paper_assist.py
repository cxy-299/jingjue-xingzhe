"""Paper assistance and current-frame negatives; synthetic != field accuracy."""
import cv2
import numpy as np
import pytest
from src.core.a4_targets import CLASS_BASE
from src.detection.printed_digit import PrintedDigitDetector
from src.detection.paper_digit_assist import paper_views
from test_a4_digit import scene
from test_printed_digit_neighbor_filter import glyph


@pytest.mark.parametrize('digit',range(10))
def test_perspective_paper_and_uneven_light(digit):
    frame=scene(str(digit),[[195,48],[424,89],[394,412],[221,366]])
    gain=np.linspace(.42,1.,640)[None,:,None]
    frame=np.clip(frame.astype(float)*gain+18,0,255).astype(np.uint8)
    detector=PrintedDigitDetector();out=detector.detect(frame)
    assert paper_views(frame)
    assert len(out)==1 and out[0].class_id==CLASS_BASE+digit,detector.status
    assert not detector.pages[0]['physical_size_verified']


@pytest.mark.parametrize('text',['','12','34','00','A','X','?','--','O'])
def test_paper_outline_cannot_invent_an_identity(text):
    assert not PrintedDigitDetector().detect(scene(text))


def test_paper_then_blank_cannot_reuse_geometry_or_identity():
    detector=PrintedDigitDetector();assert detector.detect(scene('6'))
    assert not detector.detect(np.full((480,640,3),235,np.uint8))
    assert not detector.status['paper_assist_quads']


@pytest.mark.parametrize('digit',range(10))
def test_near_digit_needs_no_paper_border(digit):
    detector=PrintedDigitDetector();out=detector.detect(glyph(str(digit)))
    assert len(out)==1 and out[0].class_id==CLASS_BASE+digit


def test_requested_digit_cannot_override_paper_read():
    out=PrintedDigitDetector().detect(scene('6'),target_class=CLASS_BASE)
    assert len(out)==1 and out[0].class_id==CLASS_BASE+6
