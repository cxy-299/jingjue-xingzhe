"""Usual GUI release: one fresh Tk process per test; all ports are fake."""
from pathlib import Path
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/board/SIN12_R20_GUI_K14_COMPAT_FIX_20261102_144549'


def main():
    collected = subprocess.run([
        sys.executable, '-m', 'pytest', '--collect-only', '-q',
        'tests/test_r20_manual_avoid_compat.py', 'tests/test_r19_console_map.py',
        'tests/test_pid_console.py', 'tests/test_sin12_fixed_console.py',
    ], cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
    assert collected.returncode == 0, collected.stdout + collected.stderr
    nodes = [n for n in collected.stdout.splitlines() if n.startswith('tests/') and '::' in n]
    assert len(nodes) == 17, nodes
    rows = []
    for i, node in enumerate(nodes):
        xml = OUT / f'isolated_{i:02}.xml'
        run = subprocess.run([
            sys.executable, '-m', 'pytest', '-q', '-rs', node, f'--junitxml={xml}',
        ], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=35)
        (OUT / f'isolated_{i:02}.log').write_text(run.stdout + run.stderr, encoding='utf-8')
        suites = list(ET.parse(xml).getroot().iter('testsuite'))
        passed = (run.returncode == 0 and sum(int(s.get('tests', 0)) for s in suites) == 1
                  and all(int(s.get(k, 0)) == 0 for s in suites for k in ('failures', 'errors', 'skipped')))
        rows.append(dict(test=node, passed=passed, exit_code=run.returncode, xml=xml.name))
        print(f'{i+1}/{len(nodes)} {"PASS" if passed else "FAIL"} {node}', flush=True)
    report = dict(passed=all(r['passed'] for r in rows), tests=rows, hardware_access=False,
                  real_hidden_Tk=True, fake_serial_only=True, actual_motor_commands=False)
    (OUT / 'ISOLATED_VALIDATION.json').write_text(json.dumps(report, indent=2) + '\n')
    assert report['passed'], report


if __name__ == '__main__':
    main()
