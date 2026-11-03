"""Synthetic printed pages only; these do not establish field OCR accuracy."""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import pytest
from src.detection.a4_digit import A4DigitDetector,CLASS_BASE,NAMES
from src.detection.factory import create_detector
from src.core.a4_targets import check_a4_identity
from src.comm.mission_readiness import check_mission_readiness
from scripts.build_a4_digit_print_page import target_image
from src.web_gui import DashboardState
from src.comm.protocol import pack_mission_request,pack_mission_observation,parse_frame
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentResult

FONT=Path('C:/Windows/Fonts/arial.ttf')
if not FONT.exists(): FONT=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')

def page(text):
    image=Image.new('RGB',(420,594),'white')
    draw=ImageDraw.Draw(image);font=ImageFont.truetype(str(FONT),300)
    for x in (20,380): draw.rectangle((x,20,x+20,40),fill='black')
    b=draw.textbbox((0,0),text,font=font)
    draw.text(((420-b[2]+b[0])/2-b[0],(594-b[3]+b[1])/2-b[1]),text,fill='black',font=font)
    return cv2.cvtColor(np.array(image),cv2.COLOR_RGB2BGR)

def scene(text,quad=None):
    target=page(text)
    if quad is None: quad=np.float32([[220,70],[410,70],[410,340],[220,340]])
    quad=np.float32(quad)
    matrix=cv2.getPerspectiveTransform(np.float32([[0,0],[419,0],[419,593],[0,593]]),quad)
    warped=cv2.warpPerspective(target,matrix,(640,480))
    mask=cv2.warpPerspective(np.ones((594,420),np.uint8)*255,matrix,(640,480))
    out=np.full((480,640,3),65,np.uint8);out[mask>0]=warped[mask>0]
    return out

@pytest.mark.parametrize('digit',range(10))
def test_printed_single_digit_and_full_page_box(digit):
    detector=A4DigitDetector();out=detector.detect(scene(str(digit)))
    assert len(out)==1,(digit,detector.status)
    assert out[0].class_id==CLASS_BASE+digit and out[0].class_name==f'a4_digit_{digit}'
    assert out[0].h_px>260 and out[0].source=='a4_digit_template'
    assert detector.pages[0]['physical_size_verified'] is False

@pytest.mark.parametrize('digit',[0,1,2,4,6,8,9])
def test_perspective_blur_and_light(digit):
    frame=scene(str(digit),[[200,72],[406,90],[423,366],[215,351]])
    frame=cv2.GaussianBlur(frame,(3,3),.6)
    out=A4DigitDetector().detect(frame)
    assert len(out)==1 and out[0].class_id==CLASS_BASE+digit

@pytest.mark.parametrize('text',['','12','A','X','?','--'])
def test_blank_multiple_and_non_digits_rejected(text):
    assert A4DigitDetector().detect(scene(text))==[]

def test_partial_page_and_nonpaper_rejected():
    assert not A4DigitDetector().detect(scene('2',[[220,-2],[410,-2],[410,268],[220,268]]))
    assert not A4DigitDetector().detect(np.full((480,640,3),255,np.uint8))

def test_duplicate_same_number_not_automatically_locked():
    detector=A4DigitDetector();left=scene('3',[[35,80],[205,80],[205,321],[35,321]])
    right=scene('3',[[420,80],[590,80],[590,321],[420,321]])
    frame=np.maximum(left,right);detections=detector.detect(frame)
    assert len(detections)==2
    state=DashboardState();state.model_classes=NAMES;state.prepare_mission('a4_digit_3')
    for i in range(4): target,_,task,_=state.process_detections(detections,i,frame)
    assert target is None and not task['task_target_confirmed']

def test_distinct_number_identity_and_wire_are_not_coco_bottle():
    state=DashboardState();state.model_classes=NAMES
    task=state.prepare_mission('a4_digit_7')
    result=parse_frame(pack_mission_request(2,task['mission_id'],task['mission_class_id'],300,'any',False))
    assert task['mission_class_id']==CLASS_BASE+7 and task['mission_class_id']!=39
    assert result['msg_type']==0x24
    with pytest.raises(ValueError): state.prepare_mission('bottle')
    with pytest.raises(ValueError): state.prepare_mission('a4_digit_7',color='red')

@pytest.mark.parametrize('digit',[6,9])
def test_upside_down_digits_cannot_swap_identity(digit):
    frame=scene(str(digit))
    assert A4DigitDetector().detect(cv2.rotate(frame,cv2.ROTATE_180))==[]


def test_no_orientation_marks_rejected():
    frame=scene('3')
    # Erase exactly the two expected top-corner printed marks.
    frame[76:94,225:244]=255;frame[76:94,390:407]=255
    assert A4DigitDetector().detect(frame)==[]


def test_unknown_letter_o_is_not_reported_as_zero():
    assert A4DigitDetector().detect(scene('O'))==[]


def test_ready_requires_class_digit_and_strategy_consistency():
    ready=dict(online=True,task_mode='mission',mission_id=3,mission_perception_tx_id=3,
        mission_perception_tx_age_ms=30,mission_class='a4_digit_2',mission_class_id=CLASS_BASE+2,
        mission_color='any',mission_strategy='a4_digits',task_lock_id=4,
        task_target_locked=True,task_target_confirmed=True)
    assert '接近' in check_mission_readiness(ready)
    for changed in (dict(mission_class_id=39),dict(mission_class_id=CLASS_BASE+3),
                    dict(mission_color='red'),dict(mission_strategy='semantic')):
        with pytest.raises(ValueError):check_mission_readiness(dict(ready,**changed))


@pytest.mark.parametrize('digit',range(10))
def test_actual_printable_raster_recognised(digit):
    target=cv2.cvtColor(np.array(target_image(digit,FONT)),cv2.COLOR_RGB2BGR)
    frame=np.full((480,640,3),65,np.uint8)
    frame[70:367,200:410]=cv2.resize(target,(210,297),interpolation=cv2.INTER_AREA)
    out=A4DigitDetector().detect(frame)
    assert len(out)==1 and out[0].class_id==CLASS_BASE+digit


def test_different_number_never_restores_previous_selected_number():
    detector=A4DigitDetector();state=DashboardState();state.model_classes=NAMES
    frame=scene('2');out=detector.detect(frame)
    state.prepare_mission('a4_digit_2')
    for i in range(6): target,rows,task,_=state.process_detections(out,i,frame)
    assert target and task['task_target_confirmed']
    token=task['task_lock_id']
    other=scene('3')
    for i in range(6,10): target,rows,task,_=state.process_detections(detector.detect(other),i,other)
    assert target is None and task['task_lock_id']==token and not task['task_target_confirmed']


def test_factory_a4_without_model_or_ultralytics_import():
    detector=create_detector({'perception':{'backend':'a4_digits'}})
    assert detector.names==NAMES
    with pytest.raises(ValueError):create_detector({'perception':{'backend':'typo'}})

def near_scene(digit, top=-40):
    return scene(str(digit),[[140,top],[500,top],[500,top+509],[140,top+509]])

@pytest.mark.parametrize('digit',range(10))
def test_full_to_partial_keeps_current_digit_and_same_lock(digit):
    detector=A4DigitDetector();state=DashboardState();state.model_classes=NAMES
    state.prepare_mission(f'a4_digit_{digit}')
    full=scene(str(digit),[[185,20],[455,20],[455,402],[185,402]])
    for i in range(6):target,_,task,_=state.process_detections(detector.detect(full),i,full)
    assert target and task['task_target_confirmed']
    token=task['task_lock_id']
    partial=near_scene(digit)
    out=detector.detect(partial)
    assert len(out)==1 and out[0].source=='a4_partial_digit'
    target,_,task,_=state.process_detections(out,7,partial)
    assert target and task['task_target_confirmed'] and task['task_lock_id']==token
    assert detector.pages[0]['visibility']=='partial_paper_intact_digit'

def test_partial_without_full_anchor_or_after_timeout_rejected(monkeypatch):
    now=[10.]
    monkeypatch.setattr('src.detection.a4_digit.time.monotonic',lambda:now[0])
    detector=A4DigitDetector()
    assert not detector.detect(near_scene(2))
    detector.detect(scene('2',[[185,20],[455,20],[455,402],[185,402]]))
    now[0]+=.751
    assert not detector.detect(near_scene(2))
    assert not detector.anchors

def test_current_digit_required_no_blank_wrong_or_cut_digit_carryover():
    detector=A4DigitDetector()
    full=scene('2',[[185,20],[455,20],[455,402],[185,402]])
    assert detector.detect(full)
    assert not detector.detect(near_scene(3))
    assert not detector.detect(np.full((480,640,3),255,np.uint8))
    assert not detector.detect(near_scene(2,top=-280))

def test_partial_cannot_prepare_new_task_even_if_anchor_exists():
    detector=A4DigitDetector();state=DashboardState();state.model_classes=NAMES
    detector.detect(scene('2',[[185,20],[455,20],[455,402],[185,402]]))
    partial=near_scene(2);out=detector.detect(partial)
    assert out
    state.prepare_mission('a4_digit_2')
    for i in range(5):target,rows,task,_=state.process_detections(out,i,partial)
    assert target is None and not task['task_target_confirmed']
    with pytest.raises(ValueError,match='完整'):
        state.prepare_mission('a4_digit_2',detection_id=rows[0]['detection_id'])
    original=state.mission.task_id
    with pytest.raises(ValueError,match='完整'):
        state.set_task_mode('lock',detection_id=rows[0]['detection_id'])
    assert state.mission.task_id==original

def test_partial_geometry_never_uses_paper_or_old_bottle_height():
    from src.core.messages import Detection
    from src.detection.mission_geometry import MissionGeometryReporter
    from src.detection.visual_tof_geometry import VisualToFCalibration
    c=VisualToFCalibration('synthetic-only',640,480,500.,500.,320.,240.,200.,3.,0.,0.,0.,150.,5000.)
    r=MissionGeometryReporter(c)
    d=Detection(39,'bottle',.95,270,140,370,340,640,480,'a4_partial_digit')
    assert r.observe(d,age_ms=0,confirmed=True) is None

def test_missing_current_digit_clears_confirmation_and_wire_visible_flags():
    detector=A4DigitDetector();state=DashboardState();state.model_classes=NAMES
    state.prepare_mission('a4_digit_2')
    full=scene('2',[[185,20],[455,20],[455,402],[185,402]])
    for i in range(6):target,_,task,_=state.process_detections(detector.detect(full),i,full)
    token=task['task_lock_id'];assert task['task_target_confirmed']
    blank=np.full((480,640,3),255,np.uint8)
    target,_,task,_=state.process_detections(detector.detect(blank),7,blank)
    assert target is None and task['task_lock_id']==token and not task['task_target_confirmed']
    assert task['task_target_visibility']=='not_confirmed'
    packet=parse_frame(pack_mission_observation(7,TargetObservation.from_detection(100,target),
        VisualAlignmentResult('SEARCH',0,0,0,'test'),7,token,False,task['mission_id']))
    assert packet['payload'][8]&3==0

def test_bad_partial_frames_do_not_extend_anchor_age(monkeypatch):
    now=[10.];monkeypatch.setattr('src.detection.a4_digit.time.monotonic',lambda:now[0])
    detector=A4DigitDetector()
    detector.detect(scene('2',[[185,20],[455,20],[455,402],[185,402]]))
    for elapsed in (.2,.5,.76):
        now[0]=10+elapsed;assert not detector.detect(near_scene(3))
    assert not detector.anchors

def test_a4_wire_class_keeps_both_bytes_for_all_numbers():
    import struct
    for n in range(10):
        obs=TargetObservation(100,True,CLASS_BASE+n,f'a4_digit_{n}',.95,5000,5000,2000,5000)
        payload=parse_frame(pack_mission_observation(n,obs,VisualAlignmentResult('CENTERED',0,0,0,'test'),n,9,True,1))['payload']
        request=parse_frame(pack_mission_request(n,1,CLASS_BASE+n))['payload']
        assert struct.unpack_from('<H',payload,10)[0]==CLASS_BASE+n
        assert struct.unpack_from('<H',request,4)[0]==CLASS_BASE+n

