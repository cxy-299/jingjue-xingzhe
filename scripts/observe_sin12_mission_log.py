"""Bounded intelligent-task logfile observation; never opens any COM port."""
import argparse,datetime,json,re,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--seconds',type=int,default=60);a=ap.parse_args()
    assert 1<=a.seconds<=120
    folder=ROOT/'output/board/logs';start=datetime.datetime.now();stamp=start.strftime('%Y%m%d_%H%M%S')
    paths=sorted(folder.glob('console*.log'),key=lambda p:p.stat().st_mtime,reverse=True)
    offsets={p:p.stat().st_size for p in paths};rows=[]
    context=paths[0].read_text(encoding='utf-8',errors='replace').splitlines()[-1800:] if paths else []
    end=time.monotonic()+a.seconds
    while time.monotonic()<end:
        for p in folder.glob('console*.log'):
            pos=offsets.get(p,0)
            if p.stat().st_size<pos:pos=0
            with p.open('rb') as f:
                f.seek(pos);data=f.read();offsets[p]=f.tell()
            if data:rows.append(dict(file=str(p),text=data.decode('utf-8',errors='replace')))
        time.sleep(1)
    selected=[];last={}
    for line in [line for r in rows for line in r['text'].splitlines()]:
        if any(s in line for s in ('MISSION','任务许可','智能任务')):selected.append(line)
        m=re.search(r'\] RX: ([JV][01] .+)',line)
        if m and last.get(m[1][0])!=m[1]:selected.append(line);last[m[1][0]]=m[1]
        if '] RX: I' in line and (' T0 ' in line or 'RX: I0 ' in line or re.search(r' F(?!00)[0-9A-F]{2} ',line)):selected.append(line)
    dest=ROOT/f'output/board/SIN12_MISSION_LIVE_{stamp}.json'
    dest.write_text(json.dumps(dict(start=start.isoformat(),end=datetime.datetime.now().isoformat(),hardware_access=False,
        read_only=True,recent_context=context,chunks=rows,transitions=selected),ensure_ascii=False,indent=2),encoding='utf-8')
    print(str(dest));print('\n'.join(selected[-85:]));print(f'Capture complete; {len(rows)} chunks; no monitor remains')
if __name__=='__main__':main()
