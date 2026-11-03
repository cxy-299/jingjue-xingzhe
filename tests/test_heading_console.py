"""Drive the actual Tk heading workflow against a fake bidirectional port."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console
from src.comm.protocol import parse_frame


@pytest.mark.parametrize('left',[True,False])
@pytest.mark.parametrize('has_heading_capability',[True,False])
@pytest.mark.parametrize('firmware',['SIN10','SIN12'])
@pytest.mark.parametrize('fault_first',[False,True])
def test_heading_gui_requests_once_renews_and_stops_after_fpga_done(monkeypatch,has_heading_capability,firmware,left,fault_first):
    sensor=b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'
    ports=[]

    class Port:
        def __init__(self,*args,**kwargs):
            self.buffer=sensor;self.writes=[];self.sequence=None;self.refreshes=0;ports.append(self)
            if has_heading_capability:self.buffer+=b'Z0 Q0000 S00 C0000 T0000 E0000\r\n'
        def read(self,count):
            data,self.buffer=self.buffer[:count],self.buffer[count:];return data
        def write(self,data):
            self.writes.append(data)
            if data.startswith(b'\xaa\x55'):
                packet=parse_frame(data);assert packet['msg_type']==0x22
                from src.comm.protocol import pack_turn_relative
                assert data==pack_turn_relative(packet['seq'],90 if left else -90,12,False)
                self.sequence=packet['seq']
                self.buffer+=f'Z1 Q{self.sequence:04X} S01 C0000 T0860 E0860\r\n'.encode()
            if data==b'G':
                self.refreshes+=1;self.buffer+=sensor
                if self.refreshes==2:
                    if fault_first:self.buffer+=sensor.replace(b'F00',b'F20')
                    else:self.buffer+=f'Z0 Q{self.sequence:04X} S03 C0860 T0860 E0000\r\n'.encode()
            if data==b'S' and self.sequence is not None and fault_first:
                self.buffer+=f'Z0 Q{self.sequence:04X} S00 C0000 T0860 E0860\r\n'.encode()
            return len(data)
        def close(self):pass

    tk=console.tk;original_tk=tk.Tk;roots=[];errors=[];texts=[]
    original_string=tk.StringVar
    def string_var(*a,**k):
        value=original_string(*a,**k);texts.append(value);return value
    def descendants(w):
        for child in w.winfo_children():yield child;yield from descendants(child)
    def make_root():
        try:root=original_tk()
        except tk.TclError as error:pytest.skip(str(error))
        roots.append(root);root.withdraw();loop=root.mainloop
        root.report_callback_exception=lambda *args:errors.append(args)
        def run():
            widgets=list(descendants(root))
            next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')=='连接').invoke()
            def start():
                next(w for w in widgets if isinstance(w,tk.Checkbutton) and w.cget('text')=='已核对 FPGA 当前运行固件').invoke()
                next(w for w in widgets if isinstance(w,tk.Checkbutton) and w.cget('text').startswith('四轮离地')).invoke()
                button=next(w for w in widgets if isinstance(w,tk.Button) and w.cget('text')==('左转90°' if left else '右转90°'))
                button.invoke()
                # Releasing and clicking again cannot cancel/restart an active turn.
                button.event_generate('<ButtonRelease-1>')
                button.invoke()
            root.after(250,start);root.after(1200,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(tk,'Tk',make_root)
    monkeypatch.setattr(tk,'StringVar',string_var)
    monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(sys,'argv',['pc_unified_console.py','--firmware',firmware])
    try:
        console.main()
        assert not errors,errors
        port=ports[0]
        assert len([w for w in port.writes if w.startswith(b'\xaa\x55')])==int(has_heading_capability)
        assert port.refreshes>=(2 if has_heading_capability else 0)
        assert port.writes[-1]==b'S'
        if has_heading_capability:assert any(('F20' if fault_first else '到角完成') in value.get() for value in texts)
        else:assert any(f'需{firmware}有效Z回传' in value.get() for value in texts)
    finally:
        for root in roots:root.destroy()
