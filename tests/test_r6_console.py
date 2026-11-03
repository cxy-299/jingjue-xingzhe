"""Actual GUI event loop, fake serial only. Recovery must never restart a wheel."""
from pathlib import Path
import struct
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console

@pytest.mark.parametrize('case',['ack','reject','lost','severe','moving','near','disconnect'])
def test_automatic_stopped_block_ack_once_without_restart(monkeypatch,tmp_path,case):
    ports=[];roots=[];errors=[]
    sample=('C'+struct.pack('>HBhhb4B4h4H',20,0,0,0,0,*([0]*4),
                *([0,3,0,0] if case=='moving' else [0]*4),*([0]*4)).hex()+'\r\n').encode()
    sensor=b'I1 T1 D'+(b'0080 H1 F11' if case=='near' else b'1000 H0 F10')+b' R00000000 P00000000 Y00000000 W2\r\n'
    status=b'O00000000'+(b'20' if case=='severe' else b'02')+b'\r\n'
    evidence=b'M2 T000 A+000 D0000 F1 E'+(b'4' if case=='severe' else b'1')+b' X+001 P0744\r\n'
    class Port:
        def __init__(self,*a,**k):
            self.buffer=sensor+sample+b'K06000000040100\r\n'+status+evidence
            self.writes=[];ports.append(self)
        def read(self,n):data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            self.writes.append(data)
            if data==b'U':
                if case=='ack':self.buffer+=b'O0104000000\r\n'
                elif case=='reject':self.buffer+=b'O0108000002\r\n'
            return len(data)
        def close(self):pass
    tk=console.tk;original=tk.Tk
    def children(w):
        for c in w.winfo_children():yield c;yield from children(c)
    def factory():
        root=original();roots.append(root);root.withdraw();loop=root.mainloop
        root.report_callback_exception=lambda *a:errors.append(a)
        def run():
            widgets=list(children(root))
            next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')=='连接').invoke()
            if case=='disconnect':root.after(250,lambda:next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')=='断开').invoke())
            root.after(1700,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',factory);monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['console','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors
        writes=ports[0].writes
        assert writes.count(b'U')==(1 if case in ('ack','reject','lost') else 0)
        assert not any(w in (b'F',b'B',b'L',b'R',b'G',b'M',b'N',b'V') for w in writes)
    finally:
        for root in roots:root.destroy()


@pytest.mark.parametrize('version,failed',[(6,False),(7,False),(5,False),(6,True),(7,True)])
@pytest.mark.parametrize('uncheck_after',[False,True])
def test_local_completion_preserves_permission_but_unchecking_stops(monkeypatch,tmp_path,version,failed,uncheck_after,release_before_completion=False):
    roots=[];ports=[];errors=[];checks=[];permission_at_end=[];writes_at_uncheck=[]
    sensor=b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'
    def status(active,state,reason):
        return f'N{active} Q0010 S{state:02X} E{reason:02X} X0A Y0F G0A H0F R01 OFF PFF\r\n'.encode()
    class Port:
        def __init__(self,*a,**k):
            self.buffer=sensor+f'K{version:02X}000000040100\r\n'.encode();self.writes=[];self.fs=0;self.pending_end=b'';ports.append(self)
        def read(self,n):data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            self.writes.append(data)
            if data==b'F':
                self.fs+=1;self.buffer+=sensor
                if self.fs==2:self.buffer+=status(1,0x87,0)
                if self.fs==4:
                    end=status(0,0x8c if failed else 0x8b,5 if failed else 0)
                    if release_before_completion:self.pending_end=end
                    else:self.buffer+=end
            return len(data)
        def close(self):pass
    tk=console.tk;original=tk.Tk
    def children(w):
        for c in w.winfo_children():yield c;yield from children(c)
    def factory():
        root=original();roots.append(root);root.withdraw();loop=root.mainloop
        root.report_callback_exception=lambda *a:errors.append(a)
        def run():
            widgets=list(children(root))
            permission=next(w for w in widgets if isinstance(w,tk.Checkbutton) and w.cget('text').startswith('四轮离地'))
            checks.append(permission)
            button=next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')=='前 F')
            next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')=='连接').invoke()
            def start():
                for w in widgets:
                    if isinstance(w,tk.Checkbutton) and (w.cget('text')=='已核对 FPGA 当前运行固件' or w.cget('text').startswith('四轮离地')):w.invoke()
                # Dispatch its real Tk press callback, even in withdrawn tests.
                import re
                callback=re.search(r'\[([^\s]+)',button.bind('<ButtonPress-1>')).group(1)
                args=['0']*19;args[14]=str(button)
                root.tk.call(callback,*args)
            def release_then_complete():
                if not ports[0].pending_end:
                    root.after(20,release_then_complete)
                    return
                import re
                callback=re.search(r'\[([^\s]+)',root.bind_all('<ButtonRelease-1>')).group(1)
                args=['0']*19;args[14]=str(button)
                root.tk.call(callback,*args)
                ports[0].buffer+=ports[0].pending_end
                ports[0].pending_end=b''
            def verify_completion():
                permission_at_end.append(int(root.getvar(permission.cget('variable'))))
                if uncheck_after:
                    writes_at_uncheck.append(len(ports[0].writes))
                    permission.invoke()
            root.after(250,start)
            if release_before_completion:root.after(300,release_then_complete)
            root.after(1050,verify_completion)
            root.after(1350,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',factory);monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['console','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors
        assert ports[0].fs>=4
        assert permission_at_end==[1], 'Local navigation termination must not uncheck operator permission'
        if uncheck_after:
            assert not int(roots[0].getvar(checks[0].cget('variable')))
            assert ports[0].writes[writes_at_uncheck[0]:]==[b'S'], 'Unchecking must stop and cancel F refresh'
        else:
            assert int(roots[0].getvar(checks[0].cget('variable')))==1
            assert (ports[0].writes[-1]==b'F') == (version>=6 and not failed and not release_before_completion)
    finally:
        for root in roots:root.destroy()


@pytest.mark.parametrize('version',[6,7])
def test_released_forward_completion_keeps_checked_permission_without_restart(monkeypatch,tmp_path,version):
    test_local_completion_preserves_permission_but_unchecking_stops(
        monkeypatch,tmp_path,version,False,False,release_before_completion=True)


@pytest.mark.parametrize('uncheck_after',[False,True])
def test_r8_capability_keeps_gui_avoidance_permission(monkeypatch,tmp_path,uncheck_after):
    test_local_completion_preserves_permission_but_unchecking_stops(
        monkeypatch,tmp_path,8,False,uncheck_after)
