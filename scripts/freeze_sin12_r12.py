"""Freeze new R12 input hashes without altering immutable R9 evidence."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
names=set(json.loads((OUT/'sin12_hdmi_r9_build_sources.json').read_text(encoding='utf-8-sig')))
names.remove('scripts\\build_sin12_r9.ps1');names.add('scripts\\build_sin12_r12.ps1')
manifest={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sorted(names)}
(OUT/'sin12_hdmi_r12_build_sources.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
software=['fpga/motor_bt_drive/pc_unified_console.py','fpga/motor_bt_drive/pc_runtime_policy.py',
          'scripts/build_nav_map.py','src/comm/autonav.py','src/comm/mission.py','src/comm/pid_tuning.py',
          'tests/test_mission_console.py','tests/test_r10_mission_contract.py','tests/test_r11_mission_contract.py','tests/test_r12_mission_contract.py']
(OUT/'sin12_hdmi_r12_software_sources.json').write_text(json.dumps(
    {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in software},indent=2),encoding='utf-8')
old=OUT/'sin12_hdmi_r9_20261030_135330/sources/fpga/sin12_hdmi'
for name in ['sin12_hdmi_system.sdc','sin12_hdmi_system.cst']:
    assert (old/name).read_bytes()==(ROOT/'fpga/sin12_hdmi'/name).read_bytes()
print(f'R12 {len(manifest)} inputs frozen; real clocks and physical constraints byte-identical to R9')
