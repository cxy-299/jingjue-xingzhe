"""Five actual firmware profiles plus measured-cell canvas. Fake ports only."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def main():
    c=subprocess.run([sys.executable,'-m','pytest','--collect-only','-q','tests/test_autonav_console.py','tests/test_r19_console_map.py'],cwd=ROOT,capture_output=True,text=True)
    assert c.returncode==0,c.stdout+c.stderr
    nodes=[n for n in c.stdout.splitlines() if n.startswith('tests/') and '::' in n];assert len(nodes)==41,nodes
    rows=[];logs=[]
    for i,n in enumerate(nodes):
        p=subprocess.run([sys.executable,'-m','pytest','-q','-rs',n,f'--junitxml={OUT}/r19_gui_{i:02d}.xml'],cwd=ROOT,capture_output=True,text=True,timeout=35)
        passed=p.returncode==0 and '1 passed' in p.stdout and 'skipped' not in p.stdout
        rows.append(dict(test=n,exit_code=p.returncode,passed=passed));logs.append(n+'\n'+p.stdout+p.stderr)
    (OUT/'r19_console_validation.json').write_text(json.dumps(dict(all_passed=all(r['passed'] for r in rows),tests=rows,hardware_access=False),indent=2))
    (OUT/'r19_console_validation.log').write_text('\n'.join(logs),encoding='utf8')
    print(sum(r['passed'] for r in rows),'/',len(rows),'PASS fake ports only')
    assert all(r['passed'] for r in rows)
if __name__=='__main__':main()
