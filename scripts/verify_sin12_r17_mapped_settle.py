"""Supplement R17 settling coverage using the SAME verified prepared cone."""
from pathlib import Path
import json,hashlib,subprocess,re
from verify_sin12_r17_mapped_tof import verify_current_netlist
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
DEST=ROOT/'tmp/sin12_r17_mapped_settle';PREP=ROOT/'tmp/sin12_r17_mapped_recovery'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    digest=verify_current_netlist()
    parent=json.loads((OUT/'SIN12_R17_MAPPED_RECOVERY_SEARCH_VALIDATION.json').read_text())
    assert parent['passed'] and parent['netlist_sha256']==digest and not parent['internal_forces']
    assert sha(PREP/'mapped.v')==parent['mapped_wrapper_sha256']
    DEST.mkdir(parents=True,exist_ok=True)
    bench=ROOT/'fpga/motor_bt_drive/tb_sin12_r17_mapped_settle.sv'
    lib=DEST.as_posix()+'/sim';log=OUT/'r17_full_system_mapped_settle_validation.log'
    script=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -work {lib} D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v {PREP.as_posix()}/mapped.v
vlog -sv -work {lib} {bench.as_posix()}
vsim -c {lib}.tb_sin12_r17_mapped_settle
run -all
quit -f
'''
    (DEST/'run.do').write_text(script)
    p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(DEST/'run.do'),'-l',str(log)],cwd=ROOT,capture_output=True,text=True,timeout=1800)
    result=log.read_text()
    assert p.returncode==0 and 'R17_ACTUAL_MAPPED_SETTLE_PASS' in result and '** Fatal' not in result,p.stdout[-5000:]+p.stderr[-5000:]
    assert verify_current_netlist()==digest
    report=dict(passed=True,hardware_access=False,internal_forces=False,netlist_sha256=digest,
      primitive_count=parent['primitive_count'],mapped_wrapper_sha256=sha(PREP/'mapped.v'),testbench_sha256=sha(bench),
      original_interface_cut_points=parent['original_interface_cut_points'],
      scenario_markers=re.findall(r'^# (R17_MAPPED_SETTLE_\S+PASS)',result,re.M),
      scope='Same actual producer/decoder/owner primitive cone at50MHz; wheel raw_speed5 forbids resume; real900ms insufficient quiet, real1040ms/new frames resumes same task; search interval checked with accelerated EXTERNAL10ms strobes >=100 samples, not real physical motion time or whole-design SDF')
    (OUT/'SIN12_R17_MAPPED_SETTLE_VALIDATION.json').write_text(json.dumps(report,indent=2))
    print('R17 mapped continuous settling and external search interval PASS')
if __name__=='__main__':main()
