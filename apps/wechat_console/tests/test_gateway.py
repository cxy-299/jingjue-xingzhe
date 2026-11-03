"""Offline tests only: fake clock/backend, loopback HTTP, no physical serial."""
import json
from pathlib import Path
import sys
import threading
import time
import urllib.error
import urllib.request
import pytest

HERE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(HERE))
from gateway.core import ControlCore, Rejected
from gateway.demo import DemoBackend
from gateway.server import Broker, serve
from gateway.pc_adapter import TkBackend, VisionProxy


class Clock:
    value=100.
    def __call__(self):return self.value
    def ms(self):return int(self.value*1000)


class FakeBackend(DemoBackend):
    enabled=True
    def ready(self):return self.enabled,'电脑撤销许可'
    def handle(self,name,p):
        self.last_thread=threading.get_ident()
        return super().handle(name,p)


@pytest.fixture
def system():
    clock=Clock();backend=FakeBackend(clock);core=ControlCore(backend,clock,clock.ms)
    session=core.open_session('test')['session_id'];seq=0
    def action(name,payload=None,**extra):
        nonlocal seq
        seq+=1
        return core.action(dict(session_id=session,seq=seq,deadline_ms=clock.ms()+500,action=name,payload=payload or {},**extra))
    return clock,backend,core,action


def test_no_motion_before_explicit_arm(system):
    clock,b,c,do=system
    with pytest.raises(Rejected):do('manual.move',{'direction':'F'})
    assert b.data['direction']=='S'
    do('arm');do('manual.move',{'direction':'F'});assert b.data['direction']=='F'
    clock.value+=.401;c.tick();assert not c.armed and b.data['direction']=='S'
    with pytest.raises(Rejected):do('heartbeat')
    assert b.data['direction']=='S'


def test_replay_deadline_and_session_replacement(system):
    clock,b,c,do=system
    do('arm');old=c.session
    item=dict(session_id=old,seq=10,deadline_ms=clock.ms()+300,action='manual.move',payload={'direction':'F'})
    c.action(item)
    with pytest.raises(Rejected):c.action(item)
    item.update(seq=11,deadline_ms=clock.ms()-1)
    with pytest.raises(Rejected):c.action(item)
    item.update(seq=12,deadline_ms=clock.ms()+801)
    with pytest.raises(Rejected):c.action(item)
    c.open_session('other');assert b.data['direction']=='S' and not c.armed
    item.update(deadline_ms=clock.ms()+300)
    with pytest.raises(Rejected):c.action(item)


def test_permission_loss_local_takeover_and_no_heartbeat_rearm(system):
    clock,b,c,do=system
    do('arm');do('manual.move',{'direction':'F'});b.enabled=False;c.tick()
    assert not c.armed and b.data['direction']=='S'
    b.enabled=True
    with pytest.raises(Rejected):do('heartbeat')
    do('arm');c.local_stop();assert not c.armed
    with pytest.raises(Rejected):do('manual.move',{'direction':'B'})


def test_edit_parameters_stops_and_does_not_arm(system):
    clock,b,c,do=system
    do('arm');do('manual.move',{'direction':'F'})
    do('vision.prepare',{'digit':7,'arrival_mm':200})
    assert not c.armed and b.data['direction']=='S'
    do('nav.preview',{'goal':[17,17]})
    with pytest.raises(Rejected):do('nav.start')
    do('arm');do('nav.start');assert b.data['tasks']['active']
    do('stop');assert not b.data['tasks']['active']


def test_release_rejects_delayed_old_press(system):
    clock,b,c,do=system
    do('arm');sid=c.session
    c.action(dict(session_id=sid,seq=4,deadline_ms=clock.ms()+500,action='manual.release'))
    with pytest.raises(Rejected):c.action(dict(session_id=sid,seq=3,deadline_ms=clock.ms()+500,action='manual.move',payload={'direction':'F'}))
    assert b.data['direction']=='S'


def test_expired_broker_job_never_executes(system):
    clock,b,c,do=system
    do('arm');broker=Broker(c);errors=[]
    def worker():
        try:broker.call('action',dict(session_id=c.session,seq=2,deadline_ms=clock.ms()+500,action='manual.move',payload={'direction':'F'}))
        except Rejected as e:errors.append(e.status)
    thread=threading.Thread(target=worker);thread.start();thread.join(1)
    assert errors==[504];broker.pump();assert b.data['direction']=='S'


def test_broker_owner_thread_and_bad_input_stops(system):
    clock,b,c,do=system
    do('arm');broker=Broker(c);result=[]
    def request():result.append(broker.call('action',dict(session_id=c.session,seq=2,deadline_ms=clock.ms()+500,action='manual.move',payload={'direction':'F'})))
    thread=threading.Thread(target=request);thread.start();time.sleep(.02);broker.pump();thread.join(1)
    assert result and b.last_thread==threading.get_ident()
    errors=[]
    def invalid():
        try:broker.call('action',dict(session_id=c.session,seq=3,deadline_ms=clock.ms()+500,action='manual.move',payload={'direction':'INVALID'}))
        except Rejected as e:errors.append(e.status)
    thread=threading.Thread(target=invalid);thread.start();time.sleep(.02);broker.pump();thread.join(1)
    assert errors==[400] and not c.armed and b.data['direction']=='S'


def test_http_auth_and_protocol_on_loopback_only():
    b=DemoBackend();broker=Broker(ControlCore(b));token='offline-test-token-12345'
    server,thread=serve(broker,token,'127.0.0.1',0);url=f'http://127.0.0.1:{server.server_port}'
    end=threading.Event()
    def owner():
        while not end.is_set():broker.pump();end.wait(.005)
    pump=threading.Thread(target=owner);pump.start()
    def req(path,data=None,auth=token,content='application/json'):
        raw=None if data is None else (data if isinstance(data,bytes) else json.dumps(data).encode())
        r=urllib.request.Request(url+path,data=raw,headers={'Authorization':'Bearer '+auth,'Content-Type':content})
        try:
            with urllib.request.urlopen(r,timeout=2) as response:return response.status,json.load(response)
        except urllib.error.HTTPError as e:return e.code,json.load(e)
    try:
        assert req('/v1/health',auth='wrong')[0]==200
        assert req('/v1/state',auth='wrong')[0]==401
        assert req('/v1/session',{},auth='wrong')[0]==401
        assert req('/v1/nope')[0]==404
        assert req('/v1/session',b'[]')[0]==400
        assert req('/v1/session',b'{}',content='text/plain')[0]==415
        assert req('/v1/session',b'x'*8193)[0]==413
        status,s=req('/v1/session',{'label':'offline'});assert status==200
        action={'session_id':s['session_id'],'seq':1,'deadline_ms':int(time.time()*1000)+500,'action':'arm'}
        assert req('/v1/action',action)[0]==200
        assert req('/v1/action',action)[0]==409
        time.sleep(.45);assert not req('/v1/state')[1]['remote']['armed']
    finally:
        end.set();pump.join(1);broker.close();server.shutdown();server.server_close();thread.join(1)


def test_pc_permissions_cannot_be_granted_by_mobile():
    class Flag:
        value=False
        def get(self):return self.value
    class Vision:
        def snapshot(self):return {}
    flag=Flag();s={'connected':True,'firmware_confirmed':True,'motion_allowed':True,
        'capability_fresh':True,'sensors':{'ready':True,'fault':0}}
    backend=TkBackend({'snapshot':lambda:s,'dispatch':lambda n,p:None},flag,Vision())
    assert not backend.ready()[0];flag.value=True;assert backend.ready()[0]
    for key in ('connected','firmware_confirmed','motion_allowed','capability_fresh'):
        s[key]=False;assert not backend.ready()[0];s[key]=True
    s['sensors']['fault']=1;assert not backend.ready()[0]


def test_vision_proxy_config_rejects_external_or_injected_url():
    for url in ['https://example.com','http://8.8.8.8:8080','http://127.0.0.1:8080/x','http://user@127.0.0.1','http://0.0.0.0:8080']:
        with pytest.raises(ValueError):VisionProxy(url)
