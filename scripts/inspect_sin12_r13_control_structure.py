"""Inspect new full-system mapped state; never claim routed functional signoff."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/board'
net = ROOT / 'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
text = net.read_text()
report = dict(netlist_sha256=hashlib.sha256(net.read_bytes()).hexdigest(), hardware_access=False,
              full_routed_functional_signoff=False, modules={})
requirements = {
    'vision_mission_guard': ['alignment_session', 'alignment_yaw', 'centered_frames',
                             'approach_phase', 'approach_age', 'range_anchor', 'range_count',
                             'range_age', 'approach_cap', 'soft_near_count', 'recovery_ticks', 'recovery_hits'],
    'chassis_trim': ['straight_reference', 'lateral_reference', 'reference_o', 'correction_o'],
}
for name, prefixes in requirements.items():
    body = re.search(r'module ' + name + r' \([\s\S]*?endmodule', text)[0]
    cells = re.findall(r'^\s*DFF\w*\s+(\S+)\s*\(', body, re.M)
    registers = {prefix: [cell for cell in cells if cell.startswith(prefix)] for prefix in prefixes}
    inputs = re.findall(r'^\s*input\s+(?:\[[^\]]+\]\s*)?(\\\S+\s*|\w+)\s*;', body, re.M)
    report['modules'][name] = dict(registers=registers, inputs=inputs,
        dsp_cells=re.findall(r'^(?:MULT\w*|PADD\w*|ALU54D|MULTADD\w*)\s+(\S+)\s*\(', body, re.M))
    assert all(registers.values()), (name, registers)
    if name=='vision_mission_guard':
        assert re.search(r'output\s+\[4:0\]\s+mission_state;',body), 'R13 state high bit lost'
        assert len(registers['recovery_ticks'])==9 and len(registers['recovery_hits'])==2
        report['modules'][name]['recovery_tick_bits']=9
        report['modules'][name]['state_bits']=5
    assert not report['modules'][name]['dsp_cells'], 'Inspect unexpected control DSP mapping'
(OUT / 'SIN12_R13_NEW_CONTROL_NETLIST_STRUCTURE.json').write_text(json.dumps(report, indent=2))
print('Actual new full-system range/heading/short-step/trim state present; no DSP in those modules')

