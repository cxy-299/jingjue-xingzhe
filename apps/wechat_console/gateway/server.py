"""Authenticated HTTP transport; hardware callbacks only run in the owner thread."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse
import copy
import hmac
import json
import queue
import secrets
import threading
import time
from .core import ControlCore, Rejected
from .demo import DemoBackend


class Broker:
    def __init__(self, core):
        self.core=core;self.queue=queue.Queue(maxsize=32);self.lock=threading.Lock()
        self.cached=core.snapshot();self.closed=False

    def call(self, kind, payload):
        event=threading.Event();item={'kind':kind,'payload':payload,'event':event,'deadline':time.monotonic()+.65}
        try:self.queue.put_nowait(item)
        except queue.Full:raise Rejected('网关繁忙，请停止后重试',503)
        if not event.wait(.7):raise Rejected('电脑未及时处理，指令已取消',504)
        if 'error' in item:raise item['error']
        return item['result']

    def pump(self):
        self.core.tick()
        for _ in range(12):
            try:item=self.queue.get_nowait()
            except queue.Empty:break
            try:
                if self.closed or time.monotonic()>item['deadline']:raise Rejected('排队指令已失效',504)
                if item['kind']=='session':item['result']=self.core.open_session(str(item['payload'].get('label','手机'))[:40])
                else:item['result']=self.core.action(item['payload'])
            except Rejected as e:item['error']=e
            except (ValueError,TypeError,KeyError) as e:
                self.core.revoke('操作参数无效，已停车');item['error']=Rejected(str(e),400)
            except Exception:item['error']=Rejected('电脑操作失败，已撤销手机许可',503);self.core.revoke('电脑操作异常')
            finally:item['event'].set()
        with self.lock:self.cached=self.core.snapshot()

    def state(self):
        with self.lock:return copy.deepcopy(self.cached)

    def close(self):self.closed=True;self.core.revoke('网关已关闭');self.pump()


def serve(broker, token, host='127.0.0.1', port=8765, vision=None):
    if len(token)<12:raise ValueError('配对码至少12个字符')
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def send_json(self,code,payload):
            body=json.dumps(payload,ensure_ascii=False,allow_nan=False).encode()
            self.send_response(code);self.send_header('Content-Type','application/json; charset=utf-8')
            self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers()
            try:self.wfile.write(body)
            except (BrokenPipeError,ConnectionResetError):pass
        def authorized(self):
            return hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+token)
        def do_GET(self):
            path=self.path.split('?',1)[0]
            if path=='/v1/health':self.send_json(200,{'ok':True,'protocol':1,'server_time_ms':int(time.time()*1000),'demo':broker.state()['demo']});return
            if not self.authorized():self.send_json(401,{'error':'配对码不正确'});return
            if path=='/v1/state':self.send_json(200,broker.state())
            elif path=='/v1/vision/frame' and vision is not None:
                try:
                    body=vision.frame();self.send_response(200);self.send_header('Content-Type','image/jpeg');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
                except Exception:self.send_json(503,{'error':'当前相机画面不可用'})
            else:self.send_json(404,{'error':'接口不存在'})
        def do_POST(self):
            if not self.authorized():self.send_json(401,{'error':'配对码不正确'});return
            try:
                if self.headers.get('Content-Type','').split(';')[0]!='application/json':raise Rejected('仅接受JSON',415)
                try:length=int(self.headers.get('Content-Length','0'))
                except ValueError:raise Rejected('长度错误',400)
                if not 0<length<=8192:raise Rejected('请求过大或为空',413)
                self.connection.settimeout(.8)
                data=json.loads(self.rfile.read(length))
                if not isinstance(data,dict):raise Rejected('参数格式错误',400)
                if self.path=='/v1/session':result=broker.call('session',data)
                elif self.path=='/v1/action':result=broker.call('action',data)
                else:raise Rejected('接口不存在',404)
                self.send_json(200,result)
            except Rejected as e:self.send_json(e.status,{'error':str(e)})
            except (ValueError,TypeError,TimeoutError):self.send_json(400,{'error':'JSON或请求格式错误'})
    server=ThreadingHTTPServer((host,port),Handler);server.daemon_threads=True
    thread=threading.Thread(target=server.serve_forever,kwargs={'poll_interval':.1},daemon=True);thread.start()
    return server,thread


def main():
    parser=argparse.ArgumentParser(description='境觉行者小程序离线演示网关，不连接硬件')
    parser.add_argument('--host',default='127.0.0.1');parser.add_argument('--port',type=int,default=8765)
    args=parser.parse_args();token=secrets.token_urlsafe(18)
    broker=Broker(ControlCore(DemoBackend()));server,thread=serve(broker,token,args.host,args.port)
    print('演示网关 http://'+args.host+':'+str(server.server_port),flush=True)
    print('本次配对码: '+token,flush=True)
    print('此进程不读取串口、不连接FPGA或树莓派。',flush=True)
    try:
        while True:broker.pump();time.sleep(.02)
    except KeyboardInterrupt:pass
    finally:broker.close();server.shutdown();server.server_close();thread.join(1)

if __name__=='__main__':main()
