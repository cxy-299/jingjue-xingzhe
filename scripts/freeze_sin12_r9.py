"""Freeze R9 inputs before a single full build. Does not touch hardware."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board'
names=set(json.loads((OUT/'sin12_hdmi_r8_build_sources.json').read_text(encoding='utf-8-sig')))
names.remove('scripts\\build_sin12_r7.ps1')
names.update(('scripts\\build_sin12_r9.ps1','fpga\\motor_bt_drive\\heading_approach_control.v'))
manifest={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sorted(names)}
(OUT/'sin12_hdmi_r9_build_sources.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
software=['fpga/motor_bt_drive/pc_unified_console.py','fpga/motor_bt_drive/pc_runtime_policy.py',
          'src/comm/autonav.py','src/comm/pid_tuning.py','tests/test_autonav_console.py',
          'tests/test_r9_navigation_contract.py','tests/test_r6_runtime_policy.py']
(OUT/'sin12_hdmi_r9_software_sources.json').write_text(json.dumps(
    {name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in software},indent=2),encoding='utf-8')
old=OUT/'sin12_hdmi_r8_20261030_125627/sources/fpga/sin12_hdmi'
assert (old/'sin12_hdmi_system.sdc').read_bytes()==(ROOT/'fpga/sin12_hdmi/sin12_hdmi_system.sdc').read_bytes()
assert (old/'sin12_hdmi_system.cst').read_bytes()==(ROOT/'fpga/sin12_hdmi/sin12_hdmi_system.cst').read_bytes()
print(f'{len(manifest)} FPGA/build inputs frozen; SDC/CST byte-identical to R8; software frozen separately')
