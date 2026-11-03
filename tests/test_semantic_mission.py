import struct
from types import SimpleNamespace

import numpy as np
import pytest

from src.core.messages import Detection, TargetObservation
from src.web_gui import DashboardState
from src.comm.mission import parse_mission_status
from src.comm.protocol import pack_mission_request, pack_mission_observation, parse_frame


def d(cid=39,name='bottle',x=100):
    return Detection(cid,name,.95,x,100,x+60,240,640,480)


def test_semantics_confirm_unique_red_target_keep_identity_and_cancel():
    now=[0.0]
    state=DashboardState(clock=lambda:now[0]);state.model_classes={0:'person',39:'bottle'}
    red,blue,person=d(),d(x=350),d(0,'person',500)
    frame=np.zeros((480,640,3),dtype=np.uint8)
    frame[100:240,100:160]=(0,0,255);frame[100:240,350:410]=(255,0,0)
    task=state.prepare_mission('bottle','red',200);task_id=task['mission_id']
    for i in range(3):
        now[0]=i*.6;target,rows,task,_=state.process_detections([blue,person,red],i,frame)
        if i<2:assert target is None
    assert target is red and task['task_lock_id'] and task['mission_id']==task_id
    lock=task['task_lock_id']
    now[0]+=.6
    target,_,task,_=state.process_detections([blue,person],4,frame)
    assert target is None and task['task_lock_id']==lock
    state.set_task_mode('observe')
    assert state.mission.task_id==0


def test_ambiguous_or_discontinuous_targets_do_not_auto_lock():
    now=[0.0];state=DashboardState(clock=lambda:now[0]);state.model_classes={39:'bottle'}
    state.prepare_mission('bottle')
    for i in range(5):
        now[0]+=.6
        assert state.process_detections([d(),d(x=350)],i)[0] is None
    state.process_detections([d()],7)
    now[0]+=2
    assert state.process_detections([d()],8)[0] is None
    with pytest.raises(ValueError):state.prepare_mission('dragon')


@pytest.mark.parametrize('color,distance',[('blue',200),('red',100),('any',True)])
def test_invalid_semantic_request(color,distance):
    state=DashboardState();state.model_classes={39:'bottle'}
    with pytest.raises(ValueError):state.prepare_mission('bottle',color,distance)


def test_wire_contract_and_actual_telemetry():
    packet=parse_frame(pack_mission_request(17,0x12345678,39,200,'red',True))
    assert packet['msg_type']==0x24
    assert packet['payload']==struct.pack('<IHHBB',0x12345678,39,200,1,1)
    obs=TargetObservation.from_detection(100,d())
    packet=parse_frame(pack_mission_observation(20,obs,
        SimpleNamespace(state='CENTERED',center_error=0,vy=0),1,9,True,0x12345678,'red'))
    assert packet['msg_type']==0x15 and len(packet['payload'])==35
    assert packet['payload'][-5:]==bytes.fromhex('7856341201')
    actual=parse_mission_status('J0 Q12345678 S06 C0027 K00000009 N2')
    assert actual['state_name']=='任务完成' and actual['task_id']==0x12345678
    assert parse_mission_status('J0 Qx S06 C0027 K00000009 N2') is None


def test_manual_mission_selection_disambiguates_two_bottles_without_starting_motion():
    now=[0.0];state=DashboardState(clock=lambda:now[0]);state.model_classes={39:'bottle'}
    first,second=d(),d(x=350)
    _,rows,_,_=state.process_detections([first,second],1)
    result=state.prepare_mission('bottle',detection_id=rows[1]['detection_id'])
    lock=result['task_lock_id']
    assert lock and result['mission_selection']=='manual' and not result['mission_ready']
    for i in range(2):
        now[0]+=.6
        target,_,result,_=state.process_detections([first,second],i+2)
    assert target is second and result['mission_ready'] and result['task_lock_id']==lock
    assert result['mission_candidate_count']==2 and result['mission_fpga'] is None
    now[0]+=.6
    target,_,result,_=state.process_detections([first],4)
    assert target is None and not result['mission_ready'] and result['task_lock_id']==lock


def test_invalid_manual_choice_preserves_previous_mission_and_red_filter():
    state=DashboardState(clock=lambda:0.0);state.model_classes={39:'bottle',0:'person'}
    frame=np.zeros((480,640,3),dtype=np.uint8)
    _,rows,_,_=state.process_detections([d(),d(0,'person',350)],1,frame)
    old=state.prepare_mission('bottle')['mission_id']
    for choice,color in [(rows[1]['detection_id'],'any'),(rows[0]['detection_id'],'red'),('stale','any')]:
        with pytest.raises(ValueError):
            state.prepare_mission('bottle',color,detection_id=choice)
        assert state.mission.task_id==old


def test_mission_http_prepare_does_not_start_motion_and_invalid_color_is_rejected(tmp_path):
    import json
    import threading
    import urllib.request
    import urllib.error
    from http.server import ThreadingHTTPServer
    from src.web_gui import make_handler
    state=DashboardState();state.model_classes={39:'bottle'}
    server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(state,tmp_path/'unused.html'))
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    url=f'http://127.0.0.1:{server.server_port}/api/mission/prepare'
    def post(color, detection_id=None):
        return urllib.request.urlopen(urllib.request.Request(url,
            data=json.dumps(dict(target_class='bottle',color=color,distance_mm=200,
                                 **({'detection_id':detection_id} if detection_id else {}))).encode(),
            headers={'Content-Type':'application/json'}))
    try:
        with post('red') as response:
            assert response.status==202
            result=json.load(response)
        assert result['mission_id'] and result['task_lock_id']==0
        assert result['mission_fpga'] is None
        with pytest.raises(urllib.error.HTTPError) as error:post('blue')
        assert error.value.code==400
        assert state.mission.task_id==result['mission_id']
        _,rows,_,_=state.process_detections([d(),d(x=350)],1)
        with post('any',rows[1]['detection_id']) as response:
            result=json.load(response)
        assert result['task_lock_id'] and result['mission_selection']=='manual'
        assert state.tracker.detection.cx_px==380
    finally:server.shutdown();server.server_close();thread.join()
