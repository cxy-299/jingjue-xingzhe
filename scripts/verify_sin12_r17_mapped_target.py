"""Regress the converter extracted from the full system's actual Gowin netlist.

Recreate only the external shared inversion DFF after asserting its exact
connections in the parent guard. No forced internal nodes or control enables.
This verifies the mapped arithmetic boundary, not the entire routed system.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
NETLIST = ROOT / 'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
DEST = ROOT / 'tmp/sin12_r17_system_target'


def verify_current_netlist():
    root=Path(__file__).resolve().parents[1]
    manifest_path=root/'output/board/sin12_hdmi_r17_build_sources.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    assert all(hashlib.sha256((root/p).read_bytes()).hexdigest()==h for p,h in manifest.items())
    net=root/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
    assert net.stat().st_mtime>=manifest_path.stat().st_mtime,'Stale synthesis netlist'
    assert (root/'output/board/sin12_hdmi_r17_build_exit.txt').read_text().strip() in ('0','RUNNING')
    return hashlib.sha256(net.read_bytes()).hexdigest()

def main():
    frozen_net_hash=verify_current_netlist()
    text = NETLIST.read_text()
    module = re.search(r'module sin12_turn_target_pipeline\s*\([\s\S]*?endmodule', text)[0]
    parent = re.search(r'module imu_turn_guard\s*\([\s\S]*?endmodule', text)[0]
    assert not re.search(r'\bMULT\w*\s', module), 'Mapped target unexpectedly uses a DSP'
    for name in ('hi_q', 'lo_q', 'product_q', 'delta_q', 'sum_q'):
        assert re.search(r'DFF\w*\s+' + name + r'_', module), name
    # Match the actual first valid stage to find the optimized accept port.
    valid = re.search(r'DFFCE valid_q_0_s0\s*\((.*?)\);', module, re.S)[1]
    accept = re.search(r'\.D\((\w+)\)', valid)[1]
    assert '.CLK(clk_50m_i_d)' in valid and '.CLEAR(n177_5)' in valid
    shared = re.search(r'DFFCE inverted_s0\s*\((.*?)\);', parent, re.S)[1]
    for connection in ('.Q(inverted)', r'.D(\g_heading.requested_inverted )',
                       '.CLK(clk_50m_i_d)', '.CLEAR(n177_5)', f'.CE({accept})'):
        assert connection in shared, connection
    assert re.search(r'DFFCE inv1_s0\s*\([^;]*\.D\(inverted\)[^;]*\.CE\(valid_q\[0\]\)', module, re.S)
    DEST.mkdir(exist_ok=True)
    (DEST / 'mapped.v').write_text(module.replace('module sin12_turn_target_pipeline ',
                                                'module system_mapped_target ', 1))
    (DEST / 'wrapper.v').write_text(f'''module sin12_turn_target_pipeline(
input clk,rst_n,valid_i,input signed[15:0]angle_cdeg_i,yaw_i,input inverted_i,
output valid_o,output signed[15:0]target_o);
wire inverted;
DFFCE shared_inverted(.Q(inverted),.D(inverted_i),.CLK(clk),.CLEAR(!rst_n),.CE(valid_i));
defparam shared_inverted.INIT=1'b0;
system_mapped_target actual(.clk_50m_i_d(clk),.n177_5(!rst_n),.{accept}(valid_i),
.inverted(inverted),.\\g_heading.requested_angle (angle_cdeg_i),.turn_yaw(yaw_i),
.converted_valid(valid_o),.wrapped_target(target_o));
endmodule
''')
    lib = DEST.relative_to(ROOT).as_posix() + '/sim'
    script = f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -work {lib} D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v {DEST.as_posix()}/mapped.v {DEST.as_posix()}/wrapper.v
vlog -sv +define+GOWIN_GATE -work {lib} fpga/motor_bt_drive/tb_sin12_r7_target.sv
vsim -c {lib}.tb_sin12_r7_target
run -all
quit -f
'''
    (DEST / 'run.do').write_text(script)
    log = ROOT / 'output/board/r17_full_system_mapped_target.log'
    result = subprocess.run(['D:/software/modelism/win64/vsim.exe', '-c', '-do',
                             str(DEST / 'run.do'), '-l', str(log)], cwd=ROOT,
                            capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stdout + result.stderr
    output = log.read_text()
    assert 'R7_SIGNED_TARGET_PIPELINE_PASS vectors=2172' in output and '** Fatal' not in output
    assert verify_current_netlist()==frozen_net_hash,'Synthesis netlist changed during mapped test'
    evidence = dict(passed=True, vectors=2172, internal_forces=False, hardware_access=False,
                    scope='full-system mapped target plus actual shared parent inversion DFF',
                    full_system_functional_signoff=False, accept_port=accept,
                    netlist_sha256=hashlib.sha256(NETLIST.read_bytes()).hexdigest(),
                    shared_inversion_dff=shared, dsp_count_in_target=0)
    (ROOT / 'output/board/SIN12_R17_MAPPED_TARGET_VALIDATION.json').write_text(
        json.dumps(evidence, indent=2), encoding='utf-8')
    print('Full-system mapped target and parent shared inversion DFF: 2172 PASS')


if __name__ == '__main__':
    main()
