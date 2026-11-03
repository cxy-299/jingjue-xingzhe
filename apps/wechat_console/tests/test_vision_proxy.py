"""Use a loopback fake Pi to verify endpoint and identity fields; no real Pi."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import threading
import time
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from gateway.pc_adapter import VisionProxy


def test_current_detection_id_passes_to_original_pi_endpoint():
    received=[]
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*a):pass
        def do_GET(self):
            data=json.dumps({'online':True,'task_target_class':'a4_digit_7','fps':20,'model':'printed_digit_v4',
                'detections':[{'detection_id':42,'class_name':'a4_digit_7','confidence':.95}]}).encode()
            self.send_response(200);self.end_headers();self.wfile.write(data)
        def do_POST(self):
            received.append((self.path,json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
            self.send_response(202);self.end_headers();self.wfile.write(b'{}')
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    proxy=VisionProxy(f'http://127.0.0.1:{server.server_port}')
    try:
        deadline=time.monotonic()+2
        while not proxy.snapshot().get('online') and time.monotonic()<deadline:time.sleep(.02)
        assert proxy.snapshot()['online']
        with pytest.raises(ValueError):proxy.submit('vision.lock',{'digit':7,'detection_id':43})
        with pytest.raises(ValueError):proxy.submit('vision.lock',{'digit':6,'detection_id':42})
        proxy.submit('vision.lock',{'digit':7,'detection_id':42})
        deadline=time.monotonic()+2
        while not received and time.monotonic()<deadline:time.sleep(.02)
        assert received==[('/api/task/mode',{'mode':'follow','target_class':'a4_digit_7','detection_id':42})]
    finally:
        proxy.close();proxy.thread.join(2);server.shutdown();server.server_close();thread.join(1)
