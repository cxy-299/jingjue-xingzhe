"""Bounded read-only console-file capture. Never opens or writes a COM port."""
import argparse,datetime,json,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--seconds',type=int,default=60);a=ap.parse_args()
    assert 1<=a.seconds<=120
    folder=ROOT/'output/board/logs';start=datetime.datetime.now();stamp=start.strftime('%Y%m%d_%H%M%S')
    positions={p:p.stat().st_size for p in folder.glob('console*.log')}
    rows=[];until=time.monotonic()+a.seconds
    while time.monotonic()<until:
        for p in folder.glob('console*.log'):
            pos=positions.get(p,0);size=p.stat().st_size
            if size<pos:pos=0
            if size>pos:
                with p.open('rb') as f:f.seek(pos);data=f.read();positions[p]=f.tell()
                rows.append(dict(path=str(p),text=data.decode('utf-8',errors='replace')))
        time.sleep(1)
    dest=ROOT/f'output/board/SIN12_R9_LIVE_NAV_{stamp}.json'
    dest.write_text(json.dumps(dict(start=start.isoformat(),end=datetime.datetime.now().isoformat(),seconds=a.seconds,read_only=True,hardware_access=False,chunks=rows),ensure_ascii=False,indent=2),encoding='utf-8')
    # Summarize only task/control transitions, retaining every raw line above.
    previous={};selected=[]
    for row in rows:
        for line in row['text'].splitlines():
            if any(w in line for w in ('AUTONAV GOAL','AUTONAV REPLY','导航许可撤销')):selected.append(line)
            if '] RX: N' in line:
                frame=line.split('] RX: ',1)[1]
                if frame!=previous.get('N'):selected.append(line);previous['N']=frame
            if '] RX: I' in line and (' T0 ' in line or line.split('] RX: ',1)[1].startswith('I0')):selected.append(line)
    print(str(dest));print('\n'.join(selected[-70:]));print(f'Capture complete; {len(rows)} chunks; no monitor remains')
if __name__=='__main__':main()
