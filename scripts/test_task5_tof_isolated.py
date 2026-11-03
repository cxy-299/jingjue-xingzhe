"""Selected actual GUI regressions, each in a fresh fake-port process."""
import json
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board/task5_digit_to_tof_20261101'


def main():
    files=['tests/test_task5_digit_tof.py','tests/test_sin12_fixed_console.py',
           'tests/test_autonav_console.py','tests/test_mission_console.py']
    collected=subprocess.run([sys.executable,'-m','pytest','--collect-only','-q',*files],
                             cwd=ROOT,capture_output=True,text=True)
    assert collected.returncode==0,collected.stdout+collected.stderr
    nodes=[n for n in collected.stdout.splitlines() if n.startswith('tests/') and '::' in n]
    selected=[n for n in nodes if 'test_task5_digit_tof.py' in n or 'test_sin12_fixed_console.py' in n or
              ('test_autonav_console.py' in n and '[valid-True-18]' in n) or
              ('test_mission_console.py' in n and ('[False-SIN12-True]' in n or '[stop-SIN12-True]' in n))]
    assert len(selected)==18,selected
    rows=[];logs=[]
    for i,node in enumerate(selected):
        result=subprocess.run([sys.executable,'-m','pytest','-q','-rs',node,
                               '--junitxml='+str(OUT/f'gui_{i:02}.xml')],
                               cwd=ROOT,capture_output=True,text=True,timeout=40)
        passed=result.returncode==0 and '1 passed' in result.stdout and 'skipped' not in result.stdout
        rows.append(dict(test=node,exit_code=result.returncode,passed=passed))
        logs.append(node+'\n'+result.stdout+result.stderr)
    (OUT/'gui_validation.json').write_text(json.dumps(dict(all_passed=all(r['passed'] for r in rows),
         real_serial_opened=False,tests=rows),indent=2),encoding='utf8')
    (OUT/'gui_validation.log').write_text('\n'.join(logs),encoding='utf8')
    print(f"{sum(r['passed'] for r in rows)}/{len(rows)} fake-port GUI tests passed")
    assert all(r['passed'] for r in rows)


if __name__=='__main__':main()
