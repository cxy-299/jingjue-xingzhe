from types import SimpleNamespace
import struct
import json
from pathlib import Path
import pytest
from src.core.messages import Detection, TargetObservation
from src.detection.locked_target import LockedTarget
from src.web_gui import DashboardState
from src.comm.protocol import pack_locked_target, parse_frame
from fpga.motor_bt_drive.pc_unified_model import parse_vision_status


def det(cid=39, name='bottle', x=100):
    return Detection(cid, name, .9, x, 100, x+60, 240, 640, 480)


@pytest.mark.parametrize('cid,name', [(0,'person'),(39,'bottle'),(15,'cat'),(62,'tv')])
def test_any_supported_category_can_be_explicitly_selected(cid, name):
    clock = [10.0]
    state = DashboardState(clock=lambda:clock[0])
    target = det(cid,name)
    other = det(39,'bottle',400)
    _, rows, _, _ = state.process_detections([target,other],1)
    state.set_task_mode('search', name, rows[0]['detection_id'])
    picked, _, info, _ = state.process_detections([target,other],2)
    assert picked is target and info['task_lock_id'] != 0
    assert info['task_class_id'] == cid
    state.process_detections([target,other],3)
    state.set_task_mode('follow',name)
    assert state.task_status['task_mode']=='follow'


def test_lost_instance_does_not_switch_and_can_reappear_after_two_frames():
    tracker = LockedTarget()
    original, other = det(x=50), det(x=450)
    tracker.lock(original,7,0)
    assert tracker.update([other,det(x=55)],.5).cx_px < 100
    assert tracker.update([other],.8) is None
    assert tracker.update([original],1.0) is None
    assert tracker.update([original,other],1.5) is original
    assert tracker.token == 7 and tracker.reacquired


def appearance_scene(*items):
    import numpy as np
    frame = np.zeros((480,640,3), dtype=np.uint8)
    for detection, color in items:
        frame[int(detection.y1):int(detection.y2),
              int(detection.x1):int(detection.x2)] = color
    return frame


def test_reacquisition_uses_appearance_across_full_frame_and_keeps_identity():
    tracker = LockedTarget()
    original, returned = det(x=50), det(x=450)
    red, blue = (0,0,220), (220,0,0)
    reference = LockedTarget.appearance(appearance_scene((original,red)),original)
    tracker.lock(original,42,0,reference)
    assert tracker.update([],2) is None
    # Other class at the old location and wrong-colored bottle cannot steal lock.
    person, other = det(0,'person',50), det(x=200)
    candidates = [person,other,returned]
    frame = appearance_scene((person,red),(other,blue),(returned,red))
    features = [LockedTarget.appearance(frame,d) for d in candidates]
    assert tracker.update(candidates,20,features) is None
    assert tracker.update(candidates,20.6,features) is returned
    assert tracker.token == 42 and tracker.hits == 2 and tracker.reacquired
    assert tracker.reference_appearance is reference


def test_similar_candidates_wait_and_interrupted_confirmation_restarts():
    tracker = LockedTarget()
    original, first, second = det(x=50), det(x=300), det(x=450)
    red, blue = (0,0,220), (220,0,0)
    reference = LockedTarget.appearance(appearance_scene((original,red)),original)
    tracker.lock(original,8,0,reference)
    tracker.update([],1)
    same = [reference,reference]
    for now in (2,3,4):
        assert tracker.update([first,second],now,same) is None
        assert tracker.ambiguous and tracker.token == 8
    wrong = LockedTarget.appearance(appearance_scene((first,blue)),first)
    assert tracker.update([first],5,[wrong]) is None
    assert tracker.update([first],6,[reference]) is None
    assert tracker.update([],6.2) is None
    assert tracker.update([first],7,[reference]) is None
    assert tracker.update([first],7.6,[reference]) is first
    tracker.clear()
    assert tracker.token == 0 and tracker.reference_appearance is None
    assert tracker.update([first],8,[reference]) is None


def test_dashboard_retains_lock_and_follow_intent_through_loss_and_return():
    now = [0.0]
    state = DashboardState(clock=lambda:now[0])
    original, returned = det(x=50), det(x=450)
    red = (0,0,220)
    _,rows,_,_=state.process_detections([original],1,appearance_scene((original,red)))
    state.set_task_mode('search','bottle',rows[0]['detection_id'])
    for fid in (2,3):
        now[0] += .6
        state.process_detections([original],fid,appearance_scene((original,red)))
    state.set_task_mode('follow','bottle')
    token = state.tracker.token
    now[0] = 30
    target,_,info,_=state.process_detections([],4,appearance_scene())
    assert target is None and info['task_lock_retained'] and info['task_reacquiring']
    assert info['task_mode']=='follow' and info['task_lock_id']==token
    assert not info['task_target_confirmed']
    frame = appearance_scene((returned,red))
    target,rows,info,_=state.process_detections([returned],5,frame)
    assert target is None and not rows[0]['selected']
    now[0] += .6
    target,rows,info,_=state.process_detections([returned],6,frame)
    assert target is returned and rows[0]['selected'] and info['task_target_confirmed']
    assert info['task_mode']=='follow' and info['task_lock_id']==token
    assert not info['task_reacquiring']
    state.set_task_mode('observe')
    cleared=state.status_snapshot()
    assert not cleared['task_lock_retained'] and cleared['task_lock_id']==0


def test_ambiguous_target_and_old_click_are_rejected():
    tracker=LockedTarget()
    tracker.lock(det(),1,0)
    assert tracker.update([det(x=99),det(x=101)],.1) is None
    assert tracker.ambiguous
    now=[0.0]
    state=DashboardState(clock=lambda:now[0])
    _,rows,_,_=state.process_detections([det()],1)
    now[0]=3
    with pytest.raises(ValueError): state.set_task_mode('search','bottle',rows[0]['detection_id'])
    with pytest.raises(ValueError): state.set_task_mode('follow','person')


def test_stable_choice_survives_twenty_seconds_and_class_order_changes():
    now=[0.0]
    state=DashboardState(clock=lambda:now[0])
    bottle,person=det(x=50),det(0,'person',400)
    _,rows,_,_=state.process_detections([bottle,person],0)
    chosen=rows[0]['detection_id']
    # A human can scroll, read the page, then press confirm without a 2s race.
    for frame in range(1,35):
        now[0]=frame*.6
        detections=[person,det(x=50+frame%2)] if frame%2 else [det(x=50),person]
        state.process_detections(detections,frame)
    state.set_task_mode('search','bottle',chosen)
    assert state.tracker.detection.class_id==39 and state.tracker.token==1


def test_failed_stale_choice_preserves_existing_lock_and_revision():
    now=[0.0]
    state=DashboardState(clock=lambda:now[0])
    bottle,person=det(x=50),det(0,'person',400)
    _,rows,_,_=state.process_detections([bottle,person],0)
    bottle_id,person_id=[row['detection_id'] for row in rows]
    state.set_task_mode('search','person',person_id)
    token,revision=state.tracker.token,state.task_revision
    state.process_detections([person],1)
    with pytest.raises(ValueError):state.set_task_mode('search','bottle',bottle_id)
    assert state.tracker.token==token and state.tracker.detection.class_id==0
    assert state.task_revision==revision


def test_choice_handles_are_not_shared_or_reused_after_disappearance():
    state=DashboardState()
    _,rows,_,_=state.process_detections([det(x=50)],0)
    old_id=rows[0]['detection_id']
    _,ambiguous,_,_=state.process_detections([det(x=49),det(x=51)],1)
    assert len({row['detection_id'] for row in ambiguous})==2
    assert old_id not in {row['detection_id'] for row in ambiguous}
    state.process_detections([],2)
    _,returned,_,_=state.process_detections([det(x=50)],3)
    assert returned[0]['detection_id']!=old_id


def test_user_hand_views_reacquire_after_box_size_and_background_change():
    import numpy as np
    fixture=json.loads((Path(__file__).parent/'fixtures/sin9_hand_histograms.json').read_text())
    features={key:np.asarray(value,dtype=np.float32) for key,value in fixture['features'].items()}
    original=det(0,'person',30)
    returned=Detection(0,'person',.9,300,0,630,470,640,480)
    tracker=LockedTarget()
    tracker.lock(original,19,0,features['original_hand'])
    tracker.update([],2)
    assert tracker.update([returned],3,[features['returned_hand']]) is None
    assert tracker.update([returned],3.6,[features['returned_hand']]) is returned
    assert tracker.token==19 and tracker.reacquired


def test_weaker_unique_match_requires_three_consecutive_frames():
    red=(0,0,220);blue=(220,0,0)
    original,returned=det(x=40),det(x=450)
    first=LockedTarget.appearance(appearance_scene((original,red)),original)
    second=LockedTarget.appearance(appearance_scene((returned,blue)),returned)
    mixed=(first+second)/2
    tracker=LockedTarget();tracker.lock(original,7,0,first);tracker.update([],1)
    assert .40 < tracker.distance(mixed) < .68
    assert tracker.update([returned],2,[mixed]) is None
    assert tracker.reacquire_required==3
    assert tracker.update([returned],2.6,[mixed]) is None
    assert tracker.update([returned],3.2,[mixed]) is returned


def test_wire_packet_contains_real_lock_identity_and_invalid_target_is_explicit():
    obs=TargetObservation.from_detection(123,det(0,'person'))
    align=SimpleNamespace(state='CENTERED',center_error=0.0)
    packet=parse_frame(pack_locked_target(5,obs,align,9,lock_id=42,follow=True,confirmed=True))
    assert packet['msg_type']==0x14 and len(packet['payload'])==30
    assert packet['payload'][8]==31
    assert struct.unpack('<I',packet['payload'][26:])[0]==42
    obs.valid=False
    invalid=parse_frame(pack_locked_target(6,obs,align,10,42,True,False))
    assert invalid['payload'][8]==24  # selected+follow, not visible/confirmed
    status=parse_vision_status('V1 L1 C0000 K0000002A S06 A1')
    assert status['class_name']=='person' and status['lock_id']==42 and status['active']
    assert parse_vision_status('V1 L1 C000F K00000001 S04 A0')['class_name']=='cat'


def test_state_updates_keep_sensor_data_and_latest_task_state():
    state=DashboardState()
    state.update_status(fpga_distance_mm=333)
    state.task_status['task_state']='new'
    state.update(b'jpeg',{'online':True})
    assert state.status_snapshot()['task_state']=='new'
    assert state.status_snapshot()['fpga_distance_mm']==333
