"""Real canvas route rendering, with no serial connection or motor permission."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
import pc_unified_console as console

@pytest.mark.parametrize('goal',[(14,4),(15,16)])
def test_sin12_canvas_starts_in_board_bfs_direction(monkeypatch,tmp_path,goal):
    tk=console.tk;original=tk.Tk;roots=[];errors=[];opened=[]
    def descendants(w):
        for child in w.winfo_children():yield child;yield from descendants(child)
    def make_root():
        root=original();roots.append(root);root.withdraw();root.report_callback_exception=lambda *a:errors.append(a)
        loop=root.mainloop
        def verify():
            badge=next(w for w in descendants(root) if w.winfo_name()=='sin12_preview_alignment')
            assert 'BFS预览已对齐板端' in badge.cget('text')
            canvas=next(w for w in descendants(root) if isinstance(w,tk.Canvas) and int(w.cget('width'))==440)
            canvas.event_generate('<Button-1>',x=goal[0]*22+11,y=(19-goal[1])*22+11)
            line=next(item for item in canvas.find_all() if canvas.type(item)=='line')
            points=canvas.coords(line)
            assert points[:4]==[17.5*22,17.5*22,17.5*22,16.5*22],points[:4]
            assert points[-2:]==[(goal[0]+.5)*22,(19.5-goal[1])*22]
            root.quit()
        root.mainloop=lambda:(root.after(100,verify),root.after(2000,root.quit),loop())
        return root
    monkeypatch.setattr(tk,'Tk',make_root)
    monkeypatch.setattr(console.serial,'Serial',lambda *a,**k:opened.append((a,k)))
    monkeypatch.setattr(sys,'argv',['console','--log-dir',str(tmp_path)])
    try:
        console.main();assert not errors,errors;assert not opened
    finally:
        for root in roots:root.destroy()
