from types import SimpleNamespace
import numpy as np
import pytest
from src.core.messages import Detection
from src.detection.yolo_detector import YOLODetector


def detector():
    d = YOLODetector.__new__(YOLODetector)
    d.conf,d.iou,d.imgsz,d.device=.45,.5,416,'cpu'
    d.near_enabled,d.near_margin=True,.30
    d._near_remaining=d._frame_number=d._misses=0
    d.status={}
    return d


def bottle(name='bottle', x=240):
    return Detection(39 if name=='bottle' else 75,name,.9,x,0,x+240,480,640,480)


def test_context_prediction_maps_camera_coordinates_and_clips_padding():
    d=detector();calls=[]
    def predict(**kwargs):
        calls.append(kwargs)
        b=SimpleNamespace(xyxy=[np.array([432.,190.,692.,680.])],
                          cls=[np.array(39)],conf=[np.array(.91)])
        return [SimpleNamespace(boxes=[b],names={39:'bottle'})]
    d.model=SimpleNamespace(predict=predict)
    out=d._predict(np.zeros((480,640,3),np.uint8),.30)
    assert calls[0]['source'].shape==(864,1024,3)
    assert calls[0]['conf']==.45 and calls[0]['imgsz']==416
    item=out[0]
    assert (item.x1,item.y1,item.x2,item.y2)==(240,0,500,480)
    assert (item.frame_width,item.frame_height)==(640,480)
    assert item.source=='near_context' and item.class_name=='bottle'
    assert item.normalized_10000()['cx']==5781


def test_clipped_vase_is_not_relabelled_without_actual_bottle_prediction():
    d=detector();d._predict=lambda frame,margin=0:[bottle('vase')]
    out=d.detect(np.zeros((480,640,3),np.uint8))
    assert [x.class_name for x in out]==['vase']
    assert d.status['detector_passes']==2 and d._near_remaining==0


def test_real_context_bottle_replaces_only_overlapping_confusable_box():
    d=detector();calls=[];near=bottle();vase=bottle('vase')
    person=Detection(0,'person',.9,0,0,100,400,640,480)
    def predict(frame,margin=0):
        calls.append(margin)
        return [near] if margin else [vase,person]
    d._predict=predict
    out=d.detect(None)
    assert out==[person,near] and calls==[0,.30]
    calls.clear();out=d.detect(None)
    assert out==[near] and calls==[.30]  # no permanent double inference


def test_missed_frame_never_reuses_an_old_detection():
    d=detector();d._predict=lambda frame,margin=0:[bottle()]
    assert d.detect(None)
    d._predict=lambda frame,margin=0:[]
    for _ in range(12):
        assert d.detect(None)==[]
        assert d.status['detector_passes']<=2
    assert d._near_remaining==0


def test_no_bottle_periodically_tries_context_but_preserves_other_classes():
    d=detector();person=Detection(0,'person',.9,0,0,100,400,640,480)
    d._predict=lambda frame,margin=0:[person]
    for index in range(1,9):
        assert d.detect(None)==[person]
        assert d.status['detector_passes']==(2 if index%4==0 else 1)


@pytest.mark.parametrize('d',[
    Detection(75,'vase',.9,10,100,50,200,640,480),
    Detection(39,'bottle',.9,100,100,140,200,640,480),
    Detection(0,'person',.9,100,0,500,480,640,480),
])
def test_far_bottle_small_vase_or_person_does_not_force_close_mode(d):
    assert not YOLODetector._near(d)


def test_context_detection_uses_original_lock_and_missing_frame_still_stops():
    from src.web_gui import DashboardState
    now=[0.0]
    state=DashboardState(clock=lambda:now[0])
    original=bottle()
    _,rows,_,_=state.process_detections([original],1)
    state.set_task_mode('search','bottle',rows[0]['detection_id'])
    token=state.tracker.token
    near=Detection(39,'bottle',.92,243,0,500,475,640,480,'near_context')
    for fid in (2,3):
        now[0]+=.5
        target,rows,info,_=state.process_detections([near],fid)
    assert target is near and info['task_target_confirmed']
    assert info['task_lock_id']==token and rows[0]['source']=='near_context'
    now[0]+=.5
    target,_,info,_=state.process_detections([],4)
    assert target is None and not info['task_target_confirmed']
    assert info['task_lock_id']==token


def test_vase_is_not_an_automatic_bottle_mission_candidate():
    from src.web_gui import DashboardState
    state=DashboardState(clock=lambda:0)
    state.model_classes={39:'bottle',75:'vase'}
    state.prepare_mission('bottle','any',300)
    for frame_id in range(6):
        target,_,info,_=state.process_detections([bottle('vase')],frame_id)
        assert target is None and not info['mission_ready']
        assert info['task_lock_id']==0


def test_other_selected_categories_keep_original_single_pass_input():
    d=detector();d._near_remaining=6;calls=[]
    def predict(frame,margin=0):
        calls.append(margin)
        return [bottle('vase')]
    d._predict=predict
    for _ in range(8):d.detect(None,target_class='person')
    assert calls==[0]*8 and d._near_remaining==0
