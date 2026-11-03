"""Actual Tk buttons, fake ports only; stale O acknowledgements must not apply."""
from pathlib import Path
import struct
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console


@pytest.mark.parametrize('reply',['applied','stale','reject','severe','legacy','disconnect','wrap','arm','disable'])
def test_explicit_control_ack_and_no_motion(monkeypatch,tmp_path,reply):
    ports=[];roots=[];texts=[];errors=[]
    base=255 if reply=='wrap' else 0
    mask=0x20 if reply=='severe' else 0 if reply in ('arm','disable') else 2
    flags=1 if reply=='disable' else 8
    sample=('C'+struct.pack('>HBhhb4B4h4H',20,0,0,0,0,*([0]*12)).hex()+'\r\n').encode()
    def status(seq,flags,masks):return f'O{seq:02X}{flags:02X}0000{masks:02X}\r\n'.encode()
    class Port:
        def __init__(self,*a,**k):
            self.buffer=(b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'+sample+
                         (b'K04000000040100\r\n' if reply=='legacy' else b'K05000000040100\r\n')+status(base,flags,mask))
            self.writes=[];ports.append(self)
        def read(self,n):data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            self.writes.append(data)
            if data in (b'U',b'A',b'a'):
                if reply=='stale':self.buffer+=status(base,4,0)
                elif reply=='reject':self.buffer+=status((base+1)&255,8,mask)
                else:self.buffer+=status((base+1)&255,5 if data==b'A' else 4,0)
            return len(data)
        def close(self):pass
    tk=console.tk;original_tk=tk.Tk;original_var=tk.StringVar
    def var(*a,**k):value=original_var(*a,**k);texts.append(value);return value
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
            def operate():
                if reply=='arm':
                    for w in widgets:
                        if isinstance(w,tk.Checkbutton) and (w.cget('text').startswith('已核对ToF齐平') or w.cget('text')=='已核对 FPGA 当前运行固件'):w.invoke()
                label='启用前进避障' if reply=='arm' else '关闭前进避障' if reply=='disable' else '解除受阻'
                next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')==label).invoke()
            root.after(300,operate)
            if reply=='disconnect':root.after(500,lambda:next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')=='断开').invoke())
            root.after(1800,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',make_root);monkeypatch.setattr(tk,'StringVar',var)
    monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['console','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors
        writes=ports[0].writes;values=[v.get() for v in texts]
        assert not any(w in (b'F',b'B',b'L',b'R',b'G',b'M',b'V',b'N') for w in writes)
        actual=[w for w in writes if w in (b'U',b'A',b'a')]
        assert len(actual)==(0 if reply in ('severe','legacy','disconnect') else 1)
        assert any('受阻已解除' in v for v in values)==(reply in ('applied','wrap'))
        assert any('已获板端确认' in v for v in values)==(reply in ('arm','disable'))
        if reply=='reject':assert any('板端拒绝操作' in v for v in values)
    finally:
        for root in roots:root.destroy()
