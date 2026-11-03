"""Hidden real Tk + existing async transport + fake port; never physical COM/Pi."""
from pathlib import Path
import struct
import sys
import time
import pytest
ROOT=Path(__file__).resolve().parents[3]
sys.path[:0]=[str(ROOT),str(ROOT/'fpga/motor_bt_drive'),str(ROOT/'apps/wechat_console')]
import pc_unified_console as console
from gateway.core import ControlCore, Rejected
from gateway.pc_adapter import TkBackend


def test_mobile_calls_original_gates_and_local_stop_revokes(monkeypatch,tmp_path):
    ports=[];links=[];roots=[];errors=[];checked=[]
    class Port:
        def __init__(self,*a,**kw):self.buffer=b'';self.writes=[];ports.append(self)
        def read(self,n):data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):self.writes.append(data);return len(data)
        def close(self):pass
        def feed(self):
            common=('C'+struct.pack('>HBhhb4B4h4H',1,0,0,0,0,*([0]*4),*([0]*4),*([0]*4)).hex()+'\r\n').encode()
            self.buffer+=b'I1 T1 D0854 H0 F00 R00000000 P00000000 Y00000000 W0\r\nK14000000040100\r\nO0004000000\r\n'+common
    class Flag:
        value=False
        def get(self):return self.value
    class Vision:
        def snapshot(self):return {'online':False}
    tk=console.tk;original_root=tk.Tk;original_link=console.AsyncTrackedPort
    holder={};flag=Flag()
    def factory(root,hooks):
        core=ControlCore(TkBackend(hooks,flag,Vision()));holder.update(core=core,hooks=hooks)
        class Controller:
            def note_local_stop(self):core.local_stop()
            def local_takeover(self):core.local_stop('电脑接管')
            def close(self):core.revoke('closed')
        return Controller()
    def children(w):
        for child in w.winfo_children():yield child;yield from children(child)
    def link(*a,**kw):obj=original_link(*a,**kw);links.append(obj);return obj
    def make_root():
        root=original_root();root.withdraw();roots.append(root);root.report_callback_exception=lambda *a:errors.append(a)
        loop=root.mainloop
        def run():
            widgets=list(children(root))
            def invoke(kind,label):next(w for w in widgets if isinstance(w,kind) and w.cget('text').startswith(label)).invoke()
            invoke(tk.Button,'连接')
            def periodic():ports[0].feed();holder['core'].tick();root.after(40,periodic)
            periodic()
            sid=holder['core'].open_session('offline-test')['session_id'];seq=0
            def act(name,payload=None):
                nonlocal seq
                seq+=1
                return holder['core'].action(dict(session_id=sid,seq=seq,deadline_ms=int(time.time()*1000)+500,action=name,payload=payload or {}))
            def begin():
                s=holder['hooks']['snapshot']();assert s['connected'] and s['capability_fresh'] and s['sensors']['ready']
                assert not s['motion_allowed']
                with pytest.raises(Rejected):act('arm')
                flag.value=True
                with pytest.raises(Rejected):act('arm')
                invoke(tk.Checkbutton,'已核对 FPGA 当前运行固件');invoke(tk.Checkbutton,'四轮离地')
                act('arm');act('manual.move',{'direction':'F'})
                def release():
                    assert b'F' in ports[0].writes,ports[0].writes
                    act('manual.release');assert ports[0].writes[-1]==b'S'
                    # A local S is authoritative, including while the remote lease is valid.
                    act('arm');invoke(tk.Button,'停止 S');assert not holder['core'].armed
                    with pytest.raises(Rejected):act('heartbeat')
                    invoke(tk.Button,'断开');assert not holder['hooks']['snapshot']()['connected']
                    checked.append(True);root.quit()
                root.after(220,release)
            root.after(350,begin);root.after(3000,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(console.serial,'Serial',Port);monkeypatch.setattr(console,'AsyncTrackedPort',link)
    monkeypatch.setattr(tk,'Tk',make_root);monkeypatch.setattr(sys,'argv',['console','--firmware','SIN12','--log-dir',str(tmp_path)])
    try:console.main(remote_factory=factory);assert not errors,errors;assert checked
    finally:
        for obj in links:obj.close();obj._rx_thread.join(.3);obj._tx_thread.join(.3)
        for root in roots:root.destroy()
