from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
p=OUT/'sin12_hdmi_r20_software_sources.json'
keys=set(json.loads(p.read_text()))
keys.update(f.relative_to(ROOT).as_posix() for pattern in ['scripts/*r20*','tests/test_r20*','fpga/motor_bt_drive/*r20*'] for f in ROOT.glob(pattern) if f.is_file())
p.write_text(json.dumps({k:hashlib.sha256((ROOT/k).read_bytes()).hexdigest() for k in sorted(keys)},indent=2)+'\n')
print(len(keys),'current R20 software hashes')
