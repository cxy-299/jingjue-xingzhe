"""Bind the LAN gateway to the existing Tk controller, never a second serial owner."""
import ipaddress
import json
import queue
import secrets
import socket
import threading
import urllib.parse
import urllib.request
import tkinter as tk
from .core import ControlCore, Rejected
from .server import Broker, serve


class VisionProxy:
    def __init__(self, base):
        url=urllib.parse.urlsplit(base)
        if url.scheme!='http' or url.username or url.password or url.path not in ('','/'):
            raise ValueError('树莓派地址应为http://局域网IP:8080')
        try:address=ipaddress.ip_address(url.hostname)
        except ValueError:raise ValueError('树莓派地址需使用本地IP')
        if not (address.is_private or address.is_loopback) or address.is_unspecified or address.is_multicast:
            raise ValueError('只允许本地树莓派地址')
        self.base=base.rstrip('/');self.lock=threading.Lock();self.stop_event=threading.Event()
        self.jobs=queue.Queue(maxsize=4);self.status={'online':False,'message':'等待树莓派状态'}
        self.thread=threading.Thread(target=self._run,daemon=True);self.thread.start()

    def _request(self,path,payload=None):
        body=json.dumps(payload).encode() if payload is not None else None
        req=urllib.request.Request(self.base+path,data=body,headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=.6) as response:data=response.read(2_000_001)
        if len(data)>2_000_000:raise ValueError('树莓派响应过大')
        return data

    def submit(self,name,payload):
        digit=payload.get('digit');arrival=payload.get('arrival_mm',200)
        if type(digit) is not int or not 0<=digit<=9:raise ValueError('数字范围0至9')
        if type(arrival) is not int or not 180<=arrival<=1000:raise ValueError('到达距离范围180至1000mm')
        if name=='vision.lock':
            detection_id=payload.get('detection_id')
            if type(detection_id) is not int or detection_id<=0:raise ValueError('需点选当前可见的具体目标')
            with self.lock:rows=list(self.status.get('detections',[]))
            if not any(r.get('detection_id')==detection_id and r.get('class_name')==f'a4_digit_{digit}' for r in rows):
                raise ValueError('目标已离开或数字不匹配，请刷新后点选')
            path='/api/task/mode';data={'mode':'follow','target_class':f'a4_digit_{digit}','detection_id':detection_id}
        elif name=='vision.prepare':path='/api/mission/prepare';data={'target_class':f'a4_digit_{digit}','color':'any','distance_mm':arrival}
        else:path='/api/task/mode';data={'mode':'search','target_class':f'a4_digit_{digit}'}
        try:self.jobs.put_nowait((path,data))
        except queue.Full:raise ValueError('视觉请求正在处理中')
        return {'message':'请求已排队，等待树莓派状态确认'}

    def snapshot(self):
        with self.lock:return dict(self.status)

    def frame(self):
        data=self._request('/snapshot.jpg')
        if not data.startswith(b'\xff\xd8'):raise ValueError('不是JPEG图像')
        return data

    def _run(self):
        while not self.stop_event.is_set():
            try:
                try:path,data=self.jobs.get_nowait();self._request(path,data)
                except queue.Empty:pass
                state=json.loads(self._request('/api/status'))
                category=state.get('task_target_class','a4_digit_0')
                digit=int(category[-1]) if category.startswith('a4_digit_') and category[-1:].isdigit() else None
                with self.lock:self.status={'online':bool(state.get('online')),'digit':digit,
                    'fps':state.get('fps'),'detector_ms':state.get('detector_ms'),
                    'model':state.get('model'),'message':state.get('task_state') or state.get('message'),
                    'mission_id':state.get('mission_id'),'confirmed':bool(state.get('mission_ready') or state.get('task_target_confirmed')),
                    'detections':[dict(detection_id=r.get('detection_id'),class_name=r.get('class_name'),
                        confidence=r.get('confidence')) for r in state.get('detections',[])][:20]}
            except Exception:
                with self.lock:self.status={'online':False,'message':'树莓派未连接或状态过期'}
            self.stop_event.wait(.7)

    def close(self):self.stop_event.set()


class TkBackend:
    def __init__(self,hooks,allowed,vision):self.h=hooks;self.allowed=allowed;self.vision=vision
    def ready(self):
        s=self.h['snapshot']()
        for ok,reason in [(self.allowed.get(),'请先在电脑勾选允许本次手机控制'),
                          (s['connected'],'电脑蓝牙尚未连接'),
                          (s['firmware_confirmed'],'电脑尚未核对固件'),
                          (s['motion_allowed'],'电脑尚未授予本次运动许可'),
                          (s['capability_fresh'],'等待新鲜K14能力回传'),
                          (s['sensors']['ready'],'ToF/IMU/板端状态无效或过期'),
                          (not s['sensors']['fault'],'板端保护已触发')]:
            if not ok:return False,reason
        return True,''
    def snapshot(self):
        result=self.h['snapshot']();result['desktop_enabled']=self.allowed.get()
        result['vision']=self.vision.snapshot();return result
    def tick(self):pass
    def handle(self,name,payload):
        if name.startswith('vision.'):return self.vision.submit(name,payload)
        return self.h['dispatch'](name,payload)


class DesktopGateway:
    def __init__(self,root,hooks,host,port,pi_base):
        self.root=root;self.closed=False;self.allowed=tk.BooleanVar(value=False)
        root.title('境觉行者 · 电脑中转驾驶台 · 微信小程序网关')
        self.vision=VisionProxy(pi_base);self.core=ControlCore(TkBackend(hooks,self.allowed,self.vision));self.broker=Broker(self.core)
        token=secrets.token_urlsafe(18)
        try:self.server,self.thread=serve(self.broker,token,host,port,self.vision)
        except Exception:self.vision.close();raise
        panel=tk.LabelFrame(hooks['container'],text='微信小程序局域网网关 · 仅本次进程有效')
        panel.pack(fill='x',pady=4)
        tk.Checkbutton(panel,text='允许本次手机控制（仍需原固件与运动许可）',variable=self.allowed,
                       command=self._permission_changed).pack(anchor='w')
        try:addresses=sorted(set(socket.gethostbyname_ex(socket.gethostname())[2]))
        except OSError:addresses=[]
        host_text=' / '.join('http://'+ip+':'+str(self.server.server_port) for ip in addresses if not ip.startswith('127.')) or 'http://电脑局域网IP:'+str(self.server.server_port)
        tk.Label(panel,text=host_text,anchor='w').pack(fill='x',padx=5)
        row=tk.Frame(panel);row.pack(fill='x',padx=5)
        tk.Label(row,text='本次配对码').pack(side='left');entry=tk.Entry(row,width=36)
        entry.insert(0,token);entry.configure(state='readonly');entry.pack(side='left',padx=5)
        tk.Button(row,text='撤销手机许可',command=lambda:self._revoke('电脑撤销手机许可')).pack(side='left')
        self.label=tk.Label(panel,anchor='w',fg='#075985');self.label.pack(fill='x',padx=5)
        self._pump()
    def _permission_changed(self):
        if not self.allowed.get():self._revoke('电脑撤销手机许可')
    def _revoke(self,reason):self.core.revoke(reason)
    def note_local_stop(self):self.core.local_stop()
    def local_takeover(self):self.core.local_stop('电脑本地操作接管')
    def _pump(self):
        if self.closed:return
        self.broker.pump();s=self.broker.state()['remote'];self.label.configure(text=s['reason'])
        self.timer=self.root.after(20,self._pump)
    def close(self):
        if self.closed:return
        self.closed=True;self.root.after_cancel(self.timer);self.broker.close();self.vision.close()
        self.server.shutdown();self.server.server_close();self.thread.join(1)


def factory(host='0.0.0.0',port=8765,pi_base='http://192.168.137.129:8080'):
    return lambda root,hooks:DesktopGateway(root,hooks,host,port,pi_base)
