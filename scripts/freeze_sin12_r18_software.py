"""Freeze current client/verification files separately from sealed R17 sources."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
files=set(json.loads((OUT/'sin12_hdmi_r17_software_sources.json').read_text(encoding='utf-8-sig')))
files.update(p.relative_to(ROOT).as_posix() for pattern in ('scripts/*r18*','tests/test_r18*',
             'fpga/motor_bt_drive/*r18*.sv','fpga/motor_bt_drive/*r18*.do','fpga/motor_bt_drive/*r18*.mem')
             for p in ROOT.glob(pattern) if p.is_file())
files.update(('tests/test_autonav_console.py','src/detection/paper_digit_assist.py'))
manifest={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sorted(files)}
(OUT/'sin12_hdmi_r18_software_sources.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
print(len(manifest),'software/verification source hashes')
