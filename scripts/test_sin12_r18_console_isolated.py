"""Navigation GUI only: each fake-port Tk test in an isolated process."""
import json
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]


def main():
    collect=subprocess.run([sys.executable,'-m','pytest','--collect-only','-q','tests/test_autonav_console.py'],
                           cwd=ROOT,capture_output=True,text=True)
    assert collect.returncode==0,collect.stdout+collect.stderr
    nodes=[n for n in collect.stdout.splitlines() if n.startswith('tests/') and '::' in n]
    assert len(nodes)==32,nodes
    rows=[];logs=[]
    for node in nodes:
        run=subprocess.run([sys.executable,'-m','pytest','-q','-rs',node],cwd=ROOT,
                           capture_output=True,text=True,timeout=35)
        passed=run.returncode==0 and '1 passed' in run.stdout and 'skipped' not in run.stdout
        rows.append(dict(test=node,exit_code=run.returncode,passed=passed))
        logs.append(node+'\n'+run.stdout+run.stderr)
    out=ROOT/'output/board'
    (out/'r18_console_validation.log').write_text('\n'.join(logs),encoding='utf8')
    (out/'r18_console_validation.json').write_text(json.dumps(dict(all_passed=all(r['passed'] for r in rows),
       hardware_access=False,tests=rows),indent=2),encoding='utf8')
    print(f"{sum(r['passed'] for r in rows)}/{len(rows)} isolated navigation GUI cases passed; fake serial only")
    assert all(r['passed'] for r in rows)


if __name__=='__main__':main()
