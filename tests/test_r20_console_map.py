"""Real hidden Tk canvas; fake UART only. Assert actual drawn cell coordinates."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console
from src.comm.protocol import parse_frame

def test_r20_obstacle_canvas_is_stopped_point_not_robot_or_goal(monkeypatch,tmp_path):
    sensor=b'I1 T1 D1500 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'
    roots=[];ports=[];links=[];errors=[];checked=[]
    class Port:
        def __init__(self,*a,**kw):
            self.seq=0;self.buffer=sensor+b'K14000000040100\r\nN0 Q0000 S00 E00 X00 Y00 G00 H00 R00 OFF PFF\r\n';ports.append(self)
        def read(self,n):data,self.buffer=self.buffer[:n],self.buffer[n:];return data
        def write(self,data):
            if data.startswith(b'\xaa\x55'):self.seq=parse_frame(data)['seq']
            if data==b'N':
                self.buffer+=sensor+f'K14000000040100\r\nN1 Q{self.seq:04X} S0F E00 X11 Y04 G11 H0B R01 O11 P07\r\n'.encode()
            return len(data)
        def close(self):pass
    tk=console.tk;original_root=tk.Tk;original_link=console.AsyncTrackedPort
    def make_link(*a,**kw):
        obj=original_link(*a,**kw);links.append(obj);return obj
    def descendants(w):
        for child in w.winfo_children():yield child;yield from descendants(child)
    def make_root():
        root=original_root();roots.append(root);root.withdraw();root.report_callback_exception=lambda *a:errors.append(a)
        loop=root.mainloop
        def run():
            widgets=list(descendants(root))
            def invoke(kind,text):next(w for w in widgets if isinstance(w,kind) and w.cget('text').startswith(text)).invoke()
            invoke(tk.Button,'连接')
            def prepare():
                invoke(tk.Button,'人工确认当前位置')
                canvas=next(w for w in widgets if isinstance(w,tk.Canvas) and int(w.cget('width'))==440)
                canvas.event_generate('<Button-1>',x=17*22+11,y=8*22+11)
                invoke(tk.Radiobutton,'板内规划绕障')
                invoke(tk.Checkbutton,'已核对 FPGA 当前运行固件');invoke(tk.Checkbutton,'四轮离地')
                invoke(tk.Checkbutton,'已核对地图/障碍')
                next(w for w in widgets if w.winfo_name()=='tof_setback').insert(0,'0')
                invoke(tk.Checkbutton,'已核对20×22cm');invoke(tk.Button,'只发终点')
                def inspect():
                    marked=[i for i in canvas.find_all() if canvas.type(i)=='rectangle' and canvas.itemcget(i,'fill')=='#ffda55']
                    assert len(marked)==1
                    assert canvas.coords(marked[0])==[17*22.,12*22.,18*22.,13*22.]
                    assert any(canvas.type(i)=='text' and canvas.itemcget(i,'text')=='测' for i in canvas.find_all())
                    invoke(tk.Button,'断开')
                    assert not any(canvas.type(i)=='rectangle' and canvas.itemcget(i,'fill')=='#ffda55' for i in canvas.find_all())
                    checked.append(True);root.quit()
                root.after(1100,inspect)
            root.after(250,prepare);root.after(5000,root.quit);loop()
        root.mainloop=run;return root
    monkeypatch.setattr(console,'AsyncTrackedPort',make_link);monkeypatch.setattr(console.serial,'Serial',Port)
    monkeypatch.setattr(tk,'Tk',make_root)
    monkeypatch.setattr(sys,'argv',['console','--firmware','SIN12','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors;assert checked
    finally:
        for link in links:link.close();link._rx_thread.join(.3);link._tx_thread.join(.3)
        for root in roots:root.destroy()
