"""Real Tk mission workflow, fake transport, real wire/telemetry contracts."""
import io
import json
from pathlib import Path
import sys
import time
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console
from src.comm.protocol import parse_frame


@pytest.fixture(autouse=True)
def close_background_transports(monkeypatch):
    original=console.AsyncTrackedPort
    links=[]
    def create(*args, **kwargs):
        link=original(*args, **kwargs);links.append(link);return link
    monkeypatch.setattr(console,'AsyncTrackedPort',create)
    yield
    for link in links:
        link.close()
        link._rx_thread.join(timeout=.3)
        link._tx_thread.join(timeout=.3)


@pytest.mark.parametrize('capability',[True,False])
@pytest.mark.parametrize('firmware',['SIN11','SIN12'])
@pytest.mark.parametrize('late_loss',[True,False,'stop','yaw_fault','pc_jitter','board_timeout','recover','pc_jitter_417'])
def test_gui_mission_requires_actual_capability_and_stops_on_fpga_success(monkeypatch,capability,firmware,late_loss):
    sensor=b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'
    ports=[]
    class Port:
        def __init__(self,*a,**k):
            self.buffer=(b'K0F000000040100\r\n' if late_loss=='pc_jitter_417' else b'')+sensor+(b'J0 Q00000000 S00 CFFFF K00000000 N0\r\n' if capability else b'')
            self.writes=[];self.refreshes=0;ports.append(self)
        def read(self,n):
            data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            self.writes.append(data)
            if data.startswith(b'\xaa\x55'):
                packet=parse_frame(data);assert packet['msg_type']==0x24
                self.buffer+=b'J1 Q12345678 S01 C0027 K00000000 N0\r\n'
            if data==b'M':
                self.refreshes+=1;self.buffer+=sensor
                if late_loss=='board_timeout' and self.refreshes==1:
                    # Model an independent board lease expiry while Tk stalls.
                    roots[-1].after(300,lambda:setattr(self,'buffer',self.buffer+b'J0 Q12345678 S08 C0027 K00000009 N0\r\n'))
                if late_loss=='recover' and self.refreshes in (1,2):
                    self.buffer+=b'J1 Q12345678 S'+(b'10' if self.refreshes==1 else b'03')+b' C0027 K00000009 N0\r\n'
                if self.refreshes==(3 if late_loss=='recover' else 2):
                    terminal=b'0F' if late_loss=='yaw_fault' else b'08' if late_loss=='board_timeout' else b'06'
                    self.buffer+=b'J0 Q12345678 S'+terminal+b' C0027 K00000009 N0\r\n'
            return len(data)
        def close(self):pass
    payload=dict(online=True,task_mode='mission',mission_id=0x12345678,mission_class='bottle',
                 mission_class_id=39,mission_color='red',mission_distance_mm=200,
                 task_lock_id=9,task_target_locked=True,task_target_confirmed=True,
                 mission_perception_tx_id=0x12345678,mission_perception_tx_age_ms=100)
    reads=[]
    def live_status(*a,**k):
        data=dict(payload);reads.append(1)
        if late_loss=='stop' and len(reads)>1:
            time.sleep(.2)
        if late_loss is True and len(reads)>1:
            data.update(task_target_locked=False,task_target_confirmed=False)
        return io.BytesIO(json.dumps(data).encode())
    monkeypatch.setattr(console.urllib.request,'urlopen',live_status)
    tk=console.tk;original=tk.Tk;roots=[];errors=[];values=[];original_var=tk.StringVar
    def variable(*a,**k):
        result=original_var(*a,**k);values.append(result);return result
    def descendants(w):
        for child in w.winfo_children():yield child;yield from descendants(child)
    def root_factory():
        try:root=original()
        except tk.TclError as exc:pytest.skip(str(exc))
        roots.append(root);root.withdraw();loop=root.mainloop
        original_after=root.after
        def delayed_lease(ms,func=None,*args):
            if func is not None and func.__name__=='mission_lease' and ms==100:
                if late_loss=='pc_jitter':ms=266
                elif late_loss=='pc_jitter_417':ms=417
                elif late_loss=='board_timeout':ms=350
            return original_after(ms,func,*args)
        root.after=delayed_lease
        root.report_callback_exception=lambda *a:errors.append(a)
        def run():
            widgets=list(descendants(root))
            def invoke(kind,text,prefix=False):
                next(w for w in widgets if isinstance(w,kind) and
                     (w.cget('text').startswith(text) if prefix else w.cget('text')==text)).invoke()
            invoke(tk.Button,'连接')
            def setup():
                invoke(tk.Radiobutton,'智能任务');invoke(tk.Checkbutton,'已核对 FPGA 当前运行固件')
                invoke(tk.Checkbutton,'四轮离地',True);invoke(tk.Button,'读取Pi任务')
            def when_read():
                if any(v.get().startswith('Pi任务 #') for v in values):
                    invoke(tk.Button,'启动智能任务');root.after(900,root.quit)
                    if late_loss=='stop':root.after(50,lambda:invoke(tk.Button,'停止 S'))
                else:root.after(50,when_read)
            root.after(200,setup);root.after(300,when_read)
            root.after(4000,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',root_factory);monkeypatch.setattr(tk,'StringVar',variable)
    monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['pc_unified_console.py','--firmware',firmware])
    try:
        console.main();assert not errors,errors
        port=ports[0]
        executed=capability and (late_loss is False or late_loss in ('yaw_fault','pc_jitter','board_timeout','recover','pc_jitter_417'))
        assert sum(w.startswith(b'\xaa\x55') for w in port.writes)==int(executed)
        if executed and late_loss=='board_timeout':assert 1<=port.refreshes<=2
        else:assert port.refreshes==((3 if late_loss=='recover' else 2) if executed else 0)
        assert port.writes[-1]==b'S'
        if late_loss=='stop':assert len(reads)==2
        elif late_loss=='yaw_fault':
            if capability:assert any('对准偏航超过8°' in v.get() for v in values)
            else:assert any(f'需{firmware}有效J回传' in v.get() for v in values)
        elif late_loss in ('pc_jitter','recover','pc_jitter_417'):
            if capability:assert any('任务完成' in v.get() for v in values)
            else:assert any(f'需{firmware}有效J回传' in v.get() for v in values)
        elif late_loss=='board_timeout':
            if capability:assert any('运动许可超时' in v.get() for v in values)
            else:assert any(f'需{firmware}有效J回传' in v.get() for v in values)
        elif late_loss:assert any('暂不可见' in v.get() for v in values)
        elif capability:assert any('任务完成' in v.get() for v in values)
        else:assert any(f'需{firmware}有效J回传' in v.get() for v in values)
    finally:
        for root in roots:root.destroy()


def test_gui_displays_and_persists_first_fault_evidence(monkeypatch, tmp_path):
    packet = (b'I1 T1 D0400 H0 F10 R00000000 P00000000 Y00000000 W4\r\n'
              b'M3 T008 A+000 D0000 F1 E1 X+000 P0800\r\n')
    class Port:
        def __init__(self, *args, **kwargs): self.buffer=packet
        def read(self, n):
            data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self, data): return len(data)
        def close(self): pass
    tk=console.tk;original=tk.Tk;roots=[];errors=[];values=[];original_var=tk.StringVar
    def variable(*a, **k):
        result=original_var(*a, **k);values.append(result);return result
    def root_factory():
        try:root=original()
        except tk.TclError as exc:pytest.skip(str(exc))
        roots.append(root);root.withdraw();loop=root.mainloop
        root.report_callback_exception=lambda *a:errors.append(a)
        def run():root.after(700,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',root_factory);monkeypatch.setattr(tk,'StringVar',variable)
    monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['console','--firmware','SIN11','--connect','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors
        assert any('M3 连续无反馈，计数+0/10ms，占空比请求80.0%' in v.get() for v in values)
        logs=list(tmp_path.glob('console_*.log'));assert len(logs)==1
        assert 'F1 E1 X+000 P0800' in logs[0].read_text(encoding='utf-8')
    finally:
        for root in roots:root.destroy()
