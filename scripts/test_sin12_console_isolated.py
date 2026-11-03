"""Run Tk/fake-port tests in separate processes to isolate Tcl lifecycle state.

No test opens a real COM port. Skips are reported, never counted as passes.
"""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = ['tests/test_sin12_fixed_console.py', 'tests/test_autonav_console.py',
         'tests/test_heading_console.py', 'tests/test_mission_console.py',
         'tests/test_pc_unified_receive_gui.py', 'tests/test_pid_console.py', 'tests/test_r5_console.py', 'tests/test_r6_console.py',
         'tests/test_sin12_preview_alignment.py']


def main():
    collected = subprocess.run([sys.executable, '-m', 'pytest', '--collect-only', '-q', *FILES],
                               cwd=ROOT, text=True, capture_output=True)
    if collected.returncode:
        raise RuntimeError(collected.stdout + collected.stderr)
    nodes = [line.strip() for line in collected.stdout.splitlines() if line.startswith('tests/') and '::' in line]
    assert nodes
    rows, logs = [], []
    for node in nodes:
        result = subprocess.run([sys.executable, '-m', 'pytest', '-q', '-rs', node],
                                cwd=ROOT, text=True, capture_output=True, timeout=30)
        skipped = 'skipped' in result.stdout
        rows.append(dict(test=node, exit_code=result.returncode, skipped=skipped,
                         passed=result.returncode == 0 and not skipped and '1 passed' in result.stdout))
        logs.append(node + '\n' + result.stdout + result.stderr)
    dest = ROOT / 'output/board'
    (dest / 'sin12_fixed_console_validation.log').write_text('\n'.join(logs), encoding='utf-8')
    (dest / 'sin12_fixed_console_validation.json').write_text(json.dumps(
        dict(hardware_access=False, tests=rows, all_passed=all(r['passed'] for r in rows)),
        ensure_ascii=False, indent=2), encoding='utf-8')
    print(f"{sum(r['passed'] for r in rows)}/{len(rows)} passed; {sum(r['skipped'] for r in rows)} skipped; fake ports only")
    return 0 if all(r['passed'] for r in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
