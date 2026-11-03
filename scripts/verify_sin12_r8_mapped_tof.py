"""Exercise the ToF receiver extracted from the completed R8 system netlist.

Only real mapped valid/distance outputs are checked. The unused error output
is pruned in the system, so no RTL error signal substitutes for mapped evidence.
This does not simulate the whole system or authorize hardware programming.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/board'
DEST = ROOT / 'tmp/sin12_r8_system_tof'


def main():
    assert (OUT / 'sin12_hdmi_r8_build_exit.txt').read_text().strip() == '0', 'R8 build not complete'
    manifest_path = OUT / 'sin12_hdmi_r8_build_sources.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    for name, digest in manifest.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    netlist = ROOT / 'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
    assert netlist.stat().st_mtime >= manifest_path.stat().st_mtime, 'Stale pre-R8 netlist'
    text = netlist.read_text()
    modules = dict(re.findall(r'\bmodule\s+(\w+)\s*(\([\s\S]*?endmodule)', text))
    name = 'tof_ms53l2m_ascii_uart'
    receiver = 'module ' + name + ' ' + modules[name]
    ports = re.findall(r'\b(input|output)\s+(?:wire\s+)?(\[[^\]]+\]\s+)?(\w+)\s*;', receiver)
    inputs = [p[2] for p in ports if p[0] == 'input']
    outputs = [p for p in ports if p[0] == 'output']
    clk = next(p for p in inputs if 'clk_50m' in p)
    rx = next(p for p in inputs if 'tof0_uart_rx' in p)
    resets = set(inputs) - {clk, rx}
    assert len(resets) == 1 and len(inputs) == 3, ports
    reset = resets.pop()
    assert re.search(r'\.(?:CLEAR|PRESET)\(' + re.escape(reset) + r'\)', receiver), 'Inspect actual reset polarity'
    assert len(outputs) == 2, 'Inspect any additional mapped output; do not guess its meaning'
    valid = next(p[2] for p in outputs if not p[1])
    distance = next(p for p in outputs if p[1])
    width_match = re.fullmatch(r'\[(\d+):0\]\s*', distance[1])
    assert width_match and int(width_match[1]) < 16, distance
    width = int(width_match[1]) + 1
    # Recursively retain only the actual synthesized child modules. Vendor
    # cells are provided by the official simulation library, never mocked.
    selected = {name}
    pending = [name]
    while pending:
        current = pending.pop()
        for child in modules:
            if child not in selected and re.search(r'\b' + re.escape(child) + r'\s+\S+\s*\(', modules[current]):
                selected.add(child)
                pending.append(child)
    DEST.mkdir(parents=True, exist_ok=True)
    mapped = '\n\n'.join('module ' + n + ' ' + modules[n] for n in sorted(selected))
    mapped = re.sub(r'\bmodule ' + name + r'\b', 'module r8_mapped_tof', mapped)
    (DEST / 'mapped.v').write_text(mapped)
    (DEST / 'wrapper.v').write_text(f'''module tof_ms53l2m_ascii_uart(
input clk,rst_n,uart_rx_i,output[15:0]distance_mm_o,output valid_pulse_o,frame_error_o);
wire[{width-1}:0] mapped_distance;
r8_mapped_tof actual(.{clk}(clk),.{reset}(!rst_n),.{rx}(uart_rx_i),
 .{valid}(valid_pulse_o),.{distance[2]}(mapped_distance));
assign distance_mm_o={{{16-width}'d0,mapped_distance}};
assign frame_error_o=1'b0; // Unobservable in this netlist; bench disables this check.
endmodule
''')
    do = DEST / 'run.do'
    do.write_text(f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists work]}} {{vlib work}}
vlog -work work D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v mapped.v wrapper.v
vlog -sv +define+TOF_GATE -work work {{{(ROOT/'fpga/sensors/tb_tof_ascii_fault_recovery.sv').as_posix()}}}
vsim -wlf tof_r8_mapped.wlf work.tb_tof_ascii_fault_recovery
onfinish exit
run -all
quit -f
''')
    log = OUT / 'r8_full_system_mapped_tof.log'
    run = subprocess.run(['D:/software/modelism/win64/vsim.exe', '-c', '-l', str(log), '-do', str(do)],
                         cwd=DEST, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    result = log.read_text(errors='replace')
    assert run.returncode == 0 and 'TOF_ASCII_FAULT_RECOVERY_PASS checks=91' in result, result[-4000:]
    assert not re.search(r'\*\* (?:Error|Fatal|Warning)', result), result[-4000:]
    evidence = dict(passed=True, checks=91, hardware_access=False, internal_forces=False,
                    scope='Actual full-system mapped ToF receiver and UART dependencies only',
                    error_output_observable=False, checked_outputs=[valid, distance[2]],
                    netlist_sha256=hashlib.sha256(netlist.read_bytes()).hexdigest(),
                    source_sha256=manifest[next(k for k in manifest if k.endswith('tof_ms53l2m_ascii_uart.v'))],
                    child_modules=sorted(selected), ports=ports, reset_active_high=reset)
    (OUT / 'SIN12_R8_MAPPED_TOF_VALIDATION.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')
    print('R8 full-system mapped ToF overflow/framing/resync:91 checks PASS')


if __name__ == '__main__':
    main()
