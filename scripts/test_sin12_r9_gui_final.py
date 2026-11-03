"""Final changed callbacks in separate Tcl processes; fake COM ports only."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
files=['tests/test_autonav_console.py','tests/test_pc_unified_receive_gui.py','tests/test_sin12_fixed_console.py']
found=subprocess.run([sys.executable,'-m','pytest','--collect-only','-q',*files],cwd=ROOT,capture_output=True,text=True,check=True)
nodes=[s for s in found.stdout.splitlines() if s.startswith('tests/') and '::' in s]
rows=[];logs=[]
source=ROOT/'fpga/motor_bt_drive/pc_unified_console.py'
before=hashlib.sha256(source.read_bytes()).hexdigest()
for node in nodes:
    result=subprocess.run([sys.executable,'-m','pytest','-q','-rs',node],cwd=ROOT,capture_output=True,text=True,timeout=30)
    skipped='skipped' in result.stdout
    rows.append(dict(test=node,exit_code=result.returncode,skipped=skipped,passed=result.returncode==0 and not skipped and '1 passed' in result.stdout))
    logs.append(node+'\n'+result.stdout+result.stderr)
assert before==hashlib.sha256(source.read_bytes()).hexdigest(), 'GUI changed during final callback regression'
(OUT/'r9_final_gui_subset.log').write_text('\n'.join(logs),encoding='utf-8')
(OUT/'r9_final_gui_subset.json').write_text(json.dumps(dict(hardware_access=False,source_sha256=before,tests=rows,all_passed=all(r['passed'] for r in rows)),indent=2),encoding='utf-8')
# Retain the full 76-case run and replace only the cases revalidated at the
# final revision. Failures are preserved in the separate per-run logs.
p=OUT/'sin12_fixed_console_validation.json';full=json.loads(p.read_text())
lookup={r['test']:r for r in rows};full['tests']=[lookup.get(r['test'],r) for r in full['tests']]
full.update(all_passed=all(r['passed'] for r in full['tests']),final_gui_sha256=before,final_changed_callbacks='r9_final_gui_subset.json')
p.write_text(json.dumps(full,indent=2),encoding='utf-8')
print(f"Final callbacks {sum(r['passed'] for r in rows)}/{len(rows)} passed; {sum(r['skipped'] for r in rows)} skips")
sys.exit(0 if all(r['passed'] for r in rows) else 1)
