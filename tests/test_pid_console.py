"""Actual Tk callbacks and asynchronous transport, with fake Bluetooth only."""
from pathlib import Path
import struct
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console
from src.comm.protocol import parse_frame


@pytest.mark.parametrize('reply', ['applied','busy','wrong_sequence','no_capability'])
def test_stopped_pid_panel_actual_ack(monkeypatch,tmp_path,reply):
    sensor=b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'
    sample=('C'+struct.pack('>HBhhb4B4h4H',20,0,0,0,0,*([0]*12)).hex()+'\r\n').encode()
    ports=[];roots=[];texts=[];errors=[]
    class Port:
        def __init__(self,*a,**k):
            self.buffer=sensor+sample+(b'K04000000040100\r\n' if reply!='no_capability' else b'')
            self.writes=[];ports.append(self)
        def read(self,n):
            data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            self.writes.append(data)
            if data.startswith(b'\xaa\x55'):
                packet=parse_frame(data);assert packet['msg_type']==0x27
                assert struct.unpack('<HHH',packet['payload'])==(8,0,2)
                seq=packet['seq']+(reply=='wrong_sequence')
                self.buffer+=f"K04{seq&65535:04X}{'02' if reply=='busy' else '01'}080002\r\n".encode()
            return len(data)
        def close(self):pass
    tk=console.tk;original_tk=tk.Tk;original_var=tk.StringVar
    def var(*a,**k):
        value=original_var(*a,**k);texts.append(value);return value
    def children(w):
        for child in w.winfo_children():yield child;yield from children(child)
    def make_root():
        try:root=original_tk()
        except tk.TclError as exc:pytest.skip(str(exc))
        roots.append(root);root.withdraw();loop=root.mainloop
        root.report_callback_exception=lambda *args:errors.append(args)
        def run():
            widgets=list(children(root))
            next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')=='连接').invoke()
            panel=next(w for w in widgets if isinstance(w,tk.LabelFrame) and '速度PID' in w.cget('text'))
            entries=[w for w in children(panel) if isinstance(w,tk.Entry)]
            for entry,value in zip(entries,('8','0','2')):entry.delete(0,'end');entry.insert(0,value)
            root.after(300,lambda:next(w for w in children(panel) if isinstance(w,tk.Button)).invoke())
            root.after(1500,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',make_root);monkeypatch.setattr(tk,'StringVar',var)
    monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['pc_unified_console.py','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors
        packets=[w for w in ports[0].writes if w.startswith(b'\xaa\x55')]
        assert len(packets)==(0 if reply=='no_capability' else 1)
        values=[v.get() for v in texts]
        assert any('已确认生效' in v for v in values)==(reply=='applied')
        if reply=='busy':assert any('板端拒绝' in v for v in values)
        assert not any(w in (b'F',b'B',b'L',b'R',b'G',b'M',b'V') for w in ports[0].writes)
    finally:
        for root in roots:root.destroy()
