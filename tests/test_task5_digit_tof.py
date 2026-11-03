"""Actual Tk/async fake-port handoff. Never opens a physical COM port."""
from pathlib import Path
import struct
import sys
import time
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console


@pytest.mark.parametrize('case',['handoff','no_digit','wrong_class','no_token','no_ack','stale_ack',
                                 'moving','stop_pending','disconnect_pending','sensor_fault','avoid_reenabled','stop_active',
                                 'vision_silent','identity_change'])
def test_task5_digit_once_then_only_tof(monkeypatch,tmp_path,case):
    ports=[];links=[];roots=[];texts=[];errors=[]
    class Port:
        def __init__(self,*a,**k):
            self.buffer=b'';self.writes=[];self.ack=0;self.distance=650;self.fault=False
            self.avoid=True;self.visual=True;self.connected=True;self.motion_started=False;ports.append(self)
        def feed(self):
            if not self.connected:return
            hard=1 if self.fault else 0
            sensor=f'I1 T1 D{self.distance:04d} H{hard} F00 R00000000 P00000000 Y00000000 W0\r\n'.encode()
            visible=0 if case=='no_digit' or not self.visual else 1
            category='0027' if case=='wrong_class' else 'A408' if case=='identity_change' and not self.visual else 'A406'
            token=0 if case=='no_token' else 99 if case=='identity_change' and not self.visual else 42
            vision=f'V1 L{visible} C{category} K{token:08X} S02 A0\r\n'.encode()
            if case=='vision_silent' and not self.visual:vision=b''
            wheels=[5]*4 if case=='moving' else [0]*4
            common=('C'+struct.pack('>HBhhb4B4h4H',1,0,0,0,0,*([0]*4),*wheels,*([0]*4)).hex()+'\r\n').encode()
            control=f'O{self.ack:02X}{(5 if self.avoid else 4):02X}000000\r\n'.encode()
            self.buffer+=sensor+vision+common+b'K12000000040100\r\n'+control
        def read(self,n):data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            self.writes.append((time.monotonic(),data))
            if data==b'a' and case!='no_ack':
                if case!='stale_ack':self.ack=1
                self.avoid=False
            if data in (b'F',b'B'):self.motion_started=True
            return len(data)
        def close(self):self.connected=False
    tk=console.tk;original_tk=tk.Tk;original_var=tk.StringVar
    original_link=console.AsyncTrackedPort
    def wrap(*a,**k):link=original_link(*a,**k);links.append(link);return link
    def var(*a,**k):v=original_var(*a,**k);texts.append(v);return v
    def children(w):
        for child in w.winfo_children():yield child;yield from children(child)
    def make_root():
        try:root=original_tk()
        except tk.TclError as exc:pytest.skip(str(exc))
        roots.append(root);root.withdraw();root.report_callback_exception=lambda *a:errors.append(a)
        loop=root.mainloop
        def run():
            widgets=list(children(root))
            def invoke(kind,label):next(w for w in widgets if isinstance(w,kind) and w.cget('text').startswith(label)).invoke()
            invoke(tk.Button,'连接');port=ports[0]
            def periodic():
                port.feed();root.after(60,periodic)
            periodic()
            def begin():
                invoke(tk.Radiobutton,'指定目标跟随')
                invoke(tk.Checkbutton,'已核对 FPGA 当前运行固件')
                invoke(tk.Checkbutton,'四轮离地')
                invoke(tk.Button,'允许指定目标跟随')
                # Once the confirmed digit triggered, it may disappear or a
                # different object may occupy the image without another V lease.
                port.visual=False
                if case=='stop_pending':root.after(80,lambda:invoke(tk.Button,'停止 S'))
                if case=='disconnect_pending':root.after(80,lambda:invoke(tk.Button,'断开'))
            root.after(300,begin)
            if case=='handoff':
                root.after(1200,lambda:setattr(port,'distance',150))
                root.after(2000,lambda:setattr(port,'distance',200))
            if case=='sensor_fault':
                root.after(1200,lambda:setattr(port,'fault',True))
                root.after(1600,lambda:setattr(port,'fault',False))
            if case=='avoid_reenabled':root.after(1200,lambda:setattr(port,'avoid',True))
            if case=='stop_active':root.after(1200,lambda:invoke(tk.Button,'停止 S'))
            root.after(3700 if case in ('no_ack','stale_ack','moving','vision_silent','identity_change') else 2600,root.quit)
            loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',make_root);monkeypatch.setattr(tk,'StringVar',var)
    monkeypatch.setattr(console,'AsyncTrackedPort',wrap);monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['console','--firmware','SIN12','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors
        rows=ports[0].writes;sent=[b for _,b in rows]
        assert not any(b in (b'V',b'L',b'R',b'G',b'N',b'M') or b.startswith(b'\xaa\x55') for b in sent),sent
        if case in ('no_digit','wrong_class','no_token','no_ack','stale_ack','moving','stop_pending','disconnect_pending'):
            assert b'F' not in sent and b'B' not in sent,sent
        else:
            assert b'a' in sent and b'F' in sent,sent
            started=next(t for t,b in rows if b==b'F')
            disabled=next(t for t,b in rows if b==b'a')
            assert started-disabled>=.28
            if case=='handoff':
                assert b'B' in sent
                backward=sent.index(b'B');assert b'S' in sent[sent.index(b'F')+1:backward]
                assert sent[-1]==b'S'
                assert any('数字6' in v.get() and 'ToF' in v.get() for v in texts)
            elif case in ('vision_silent','identity_change'):
                assert len([b for t,b in rows if t>started+1.8 and b==b'F'])>=3,rows
                assert any('数字6' in v.get() and 'ToF' in v.get() for v in texts)
            else:
                first=next(i for i,(_,b) in enumerate(rows) if b==b'F')
                assert b'F' not in [b for t,b in rows[first+1:] if t>rows[first][0]+1.1],rows
    finally:
        for link in links:link.close();link._rx_thread.join(.3);link._tx_thread.join(.3)
        for root in roots:root.destroy()
