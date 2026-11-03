"""Real Tk interaction with fake serial; never opens a hardware COM port."""
import sys
from pathlib import Path
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console
from src.comm.protocol import parse_frame


@pytest.mark.parametrize('firmware_version',[15,16,17,18,19])
@pytest.mark.parametrize('capability',[True,False])
@pytest.mark.parametrize('reply_case',['valid','wrong_goal','wrong_position','local'])
def test_autonav_requires_actual_n_frame_and_stops_on_done(monkeypatch,capability,tmp_path,reply_case,firmware_version):
    sensor=b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'
    def status(seq,active,state):
        state_byte=state | (0x80 if reply_case=='local' else 0)
        y=2 if active or reply_case=='wrong_position' else 3
        gy=9 if reply_case=='wrong_goal' else 3
        return f'N{active} Q{seq:04X} S{state_byte:02X} E00 X11 Y{y:02X} G11 H{gy:02X} R00 OFF PFF\r\n'.encode()
    ports=[];links=[]
    class Port:
        def __init__(self,*a,**k):
            self.buffer=sensor+f'K{firmware_version:02X}000000040100\r\n'.encode()+(status(0,0,0) if capability else b'');self.writes=[];self.n=0;self.seq=0;ports.append(self)
        def read(self,n):
            data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            self.writes.append(data)
            if data.startswith(b'\xaa\x55'):
                p=parse_frame(data);assert p['msg_type']==0x26
                assert int.from_bytes(p['payload'][6:8],'little')==({15:1000,16:333,17:333,18:500,19:500}[firmware_version])
                self.seq=p['seq'];self.buffer+=status(self.seq,1,1)
            if data==b'N':
                self.n+=1;self.buffer+=sensor
                if self.n>=6:self.buffer+=status(self.seq,0,11)
            return len(data)
        def close(self):pass
    original_link=console.AsyncTrackedPort
    def link_factory(*a,**k):
        link=original_link(*a,**k);links.append(link);return link
    tk=console.tk;original_tk=tk.Tk;original_var=tk.StringVar;roots=[];errors=[];values=[]
    def variable(*a,**k):
        v=original_var(*a,**k);values.append(v);return v
    def descendants(widget):
        for child in widget.winfo_children():yield child;yield from descendants(child)
    def root_factory():
        try:root=original_tk()
        except tk.TclError as error:pytest.skip(str(error))
        roots.append(root);root.withdraw();root.report_callback_exception=lambda *a:errors.append(a)
        loop=root.mainloop
        def run():
            widgets=list(descendants(root))
            def invoke(kind,text):
                next(w for w in widgets if isinstance(w,kind) and w.cget('text').startswith(text)).invoke()
            invoke(tk.Button,'连接')
            def prepare():
                invoke(tk.Button,'人工确认当前位置')
                canvas=next(w for w in widgets if isinstance(w,tk.Canvas) and int(w.cget('width'))==440)
                assert not any(canvas.itemcget(item,'text')=='估' for item in canvas.find_all()
                               if canvas.type(item)=='text'), 'Idle N frame is not a measured robot position'
                canvas.event_generate('<Button-1>',x=17*22+11,y=16*22+11)
                invoke(tk.Radiobutton,'板内规划绕障')
                invoke(tk.Checkbutton,'已核对 FPGA 当前运行固件')
                invoke(tk.Checkbutton,'四轮离地')
                invoke(tk.Checkbutton,'已核对地图/障碍')
                entry=next(w for w in widgets if w.winfo_name()=='tof_setback');entry.insert(0,'0')
                invoke(tk.Checkbutton,'已核对20×22cm')
                invoke(tk.Button,'只发终点')
                def try_change_running_goal():
                    if capability and reply_case=='valid':
                        canvas.event_generate('<Button-1>',x=16*22+11,y=15*22+11)
                        assert any('终点已锁定' in v.get() or '执行中的已发送终点已锁定' in v.get() for v in values)
                root.after(400,try_change_running_goal)
                root.after(1500,root.quit)
            root.after(250,prepare);root.after(4000,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(console,'AsyncTrackedPort',link_factory)
    monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(tk,'Tk',root_factory);monkeypatch.setattr(tk,'StringVar',variable)
    monkeypatch.setattr(sys,'argv',['console','--firmware','SIN12','--log-dir',str(tmp_path)])
    try:
        console.main()
        assert not errors,errors
        writes=ports[0].writes
        assert sum(w.startswith(b'\xaa\x55') for w in writes)==int(capability)
        if capability:
            assert ports[0].n>=1 and writes[-1]==b'S'
            if reply_case=='valid':assert any('确认到达已发送终点' in v.get() for v in values)
            else:assert any('回执不一致' in v.get() for v in values)
        else:assert ports[0].n==0
    finally:
        for link in links:
            link.close();link._rx_thread.join(.3);link._tx_thread.join(.3)
        for root in roots:root.destroy()
