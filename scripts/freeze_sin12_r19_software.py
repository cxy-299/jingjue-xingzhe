"""R19 client/verification snapshot, including the completed task5 ToF fix."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
files=set(json.loads((OUT/'sin12_hdmi_r18_software_sources.json').read_text()))
for pattern in ('scripts/*r19*','tests/test_r19*','tests/test_task5*','scripts/test_task5*',
                'fpga/motor_bt_drive/*r19*.sv','fpga/motor_bt_drive/*r19*.do','fpga/motor_bt_drive/*r19*.mem'):
    files.update(p.relative_to(ROOT).as_posix() for p in ROOT.glob(pattern) if p.is_file())
manifest={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in sorted(files)}
(OUT/'sin12_hdmi_r19_software_sources.json').write_text(json.dumps(manifest,indent=2))
print(len(manifest),'R19 software source hashes')
