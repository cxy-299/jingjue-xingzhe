"""Local ephemeral HTTP only: no camera, Pi, serial, or motor operations."""
import json
import threading
from pathlib import Path
from http.server import ThreadingHTTPServer
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from src.web_gui import DashboardState,make_handler
from src.core.a4_targets import NAMES,CLASS_BASE


def test_a4_print_and_prepare_http_routes():
    state=DashboardState();state.model_classes=NAMES
    root=Path(__file__).resolve().parents[1]
    server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(state,root/'web/dashboard.html'))
    worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
    base=f'http://127.0.0.1:{server.server_port}'
    try:
        with urlopen(base+'/',timeout=3) as r:
            page=r.read().decode()
            assert '灵枢 · 数字靶标识别' in page
            assert '不要求A4纸四边' in page
            assert '近距瓶身识别 V1' not in page and '红瓶二次筛选' not in page
        with urlopen(base+'/a4-targets.html',timeout=3) as r:
            text=r.read().decode();assert '210mm' in text and text.count('data-digit=')==10
        data=json.dumps(dict(target_class='a4_digit_9',color='any',distance_mm=200)).encode()
        with urlopen(Request(base+'/api/mission/prepare',data=data,headers={'Content-Type':'application/json'}),timeout=3) as r:
            task=json.load(r)
        assert task['mission_class_id']==CLASS_BASE+9 and not task['task_target_confirmed']
        assert state.pending_nav_goal is None
        bad=json.dumps(dict(target_class='bottle',color='any',distance_mm=200)).encode()
        try:urlopen(Request(base+'/api/mission/prepare',data=bad,headers={'Content-Type':'application/json'}),timeout=3)
        except HTTPError as e:assert e.code==400
        else:raise AssertionError('old bottle target accepted by A4 backend')
    finally:
        server.shutdown();server.server_close();worker.join(2)

