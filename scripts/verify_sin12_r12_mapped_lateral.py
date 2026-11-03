"""Actual full-system trim lateral path, including optimized real port widths.

Promoted spin-only adder intermediates have no RTL boundary port. Leave them
unconnected (X), never fabricate them: the side/STOP test must still produce
known, correct outputs. This is explicitly not a spin-path mapped regression.
"""
from pathlib import Path
import hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board';DEST=ROOT/'tmp/sin12_r12_mapped_lateral'
def verify_current_netlist():
    root=Path(__file__).resolve().parents[1]
    manifest_path=root/'output/board/sin12_hdmi_r12_build_sources.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    assert all(hashlib.sha256((root/p).read_bytes()).hexdigest()==h for p,h in manifest.items())
    net=root/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
    assert net.stat().st_mtime>=manifest_path.stat().st_mtime,'Stale synthesis netlist'
    assert (root/'output/board/sin12_hdmi_r12_build_exit.txt').read_text().strip() in ('0','RUNNING')
    return hashlib.sha256(net.read_bytes()).hexdigest()

def main():
    frozen_net_hash=verify_current_netlist()
    # Scope is actual completed synthesis, not permission to download.
    manifest=json.loads((OUT/'sin12_hdmi_r12_build_sources.json').read_text())
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in manifest.items())
    net=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg';text=net.read_text()
    child=re.search(r'module chassis_trim \([\s\S]*?endmodule',text)[0]
    assert 'lateral_reference' in child and 'heading_correction' in child
    ports=[(d,w or '',p.strip()) for d,w,p in re.findall(r'^(input|output)\s+(\[[^\]]+\]\s*)?(\\\S+\s*|\w+)\s*;',child,re.M)]
    inputs={p:w for d,w,p in ports if d=='input'};outputs={p:w for d,w,p in ports if d=='output'}
    assert '.CLEAR(n560_6)' in child
    parent=re.search(r'module acg720_motor_bt_drive \([\s\S]*?endmodule',text)[0]
    stop_parent=re.search(r'module motor_direction_interlock \([\s\S]*?endmodule',text)[0]
    assert '.interlocked_enable_8(interlocked_enable_8)' in parent
    stop_cell=re.search(r'LUT3 interlocked_enable_s5\s*\([\s\S]*?\);',stop_parent)[0]
    stop_init=re.search(r'defparam interlocked_enable_s5\s*\.INIT=.*?;',stop_parent)[0]
    assert "8'h01" in stop_init and '.F(interlocked_enable_8)' in stop_cell
    for bit in range(3):assert f'.I{bit}(\\g_owner_pipeline.command_q [{bit}])' in stop_cell
    stop_cone=(stop_cell+'\n'+stop_init).replace('interlocked_enable_8', 'stop_from_parent')
    stop_cone=stop_cone.replace('\\g_owner_pipeline.command_q ', 'command_i')
    known={'clk_50m_i_d' :'clk','n560_6':'!rst_n','sample_tick_d':'sample_tick_i','interlocked_enable':'enable_i',
           'interlocked_enable_8':'stop_from_parent','auto_active':"owner_i==3'd1",'mission_active':"owner_i==3'd2",'heading_yaw_valid':'yaw_valid_i',
           r'\g_owner_pipeline.command_q':'command_i','owner_id':'owner_i','turn_yaw':'yaw_i','effective_target_counts':'base_i[5:0]'}
    connections=[];unconnected=[]
    for p,w in inputs.items():
        if p in known:expr=known[p]
        elif re.fullmatch(r'\\wheels\[[0-3]\]\.raw_speed',p):expr="16'd0" if '15:0' in w else "1'b0"
        elif re.fullmatch(r'n(?:24|25)\d+_\d+',p):unconnected.append(p);continue
        else:raise AssertionError(('Inspect new actual mapped port',p,w))
        connections.append(f'.{p} ({expr})')
    assert {int(re.match(r'n(\d+)_',p)[1]) for p in unconnected}==set(range(2476,2491))|set(range(2509,2524)),unconnected
    for p,w in outputs.items():
        if p in ('heading_locked','heading_reference','heading_error','heading_correction'):
            target={'heading_locked':'heading_locked_o','heading_reference':'reference_o','heading_error':'error_o','heading_correction':'correction_o'}[p]
            connections.append(f'.{p}({target})')
        elif re.fullmatch(r'wheel_targets_\d+',p):connections.append(f'.{p}(targets_o[{p.split("_")[-1]}])')
    wheel_bits=sorted(int(p.split('_')[-1]) for p in outputs if p.startswith('wheel_targets_'))
    assert wheel_bits==[16*i+b for i in range(4) for b in range(5)],wheel_bits
    # Higher wheel-target bits are eliminated after the 4..30 clamp; the mapped
    # core exposes only low five bits. Tests stay at base6 and compare known data.
    higher='\n'.join(f"assign targets_o[{16*i+15}:{16*i+5}]=11'd0;" for i in range(4))
    wrapper='''module chassis_trim #(parameter PHYSICAL_SPEEDS=1,LATERAL_HEADING=1,MISSION_PULSED=1)(
input clk,rst_n,sample_tick_i,enable_i,yaw_valid_i,input[2:0]command_i,owner_i,
input signed[15:0]yaw_i,input[15:0]base_i,input signed[15:0]speed0_i,speed1_i,speed2_i,speed3_i,
output[63:0]targets_o,output heading_locked_o,output signed[15:0]reference_o,error_o,output signed[7:0]correction_o);
'''+higher+'\nwire stop_from_parent;\n'+stop_cone+'\nr12_mapped_trim actual('+','.join(connections)+');\nendmodule\n'
    DEST.mkdir(exist_ok=True);(DEST/'mapped.v').write_text(child.replace('module chassis_trim (','module r12_mapped_trim (',1)+'\n'+wrapper)
    bench=(ROOT/'fpga/motor_bt_drive/tb_sin12_r12_trim.sv').read_text()
    bench=bench.replace('reg clk=0;',"GSR GSR(.GSRI(1'b1));\nreg clk=0;")
    # Full-design synthesis uses the upstream motor-enable invariant: invalid
    # yaw already disables the direction interlock. Do not simulate an
    # impossible parent combination (invalid yaw AND interlocked_enable).
    drive=(ROOT/'fpga/motor_bt_drive/acg720_motor_bt_drive.v').read_text(encoding='utf-8')
    assert '|| heading_yaw_valid)' in drive and '.enable_i(interlocked_enable)' in drive
    bench=bench.replace('valid=0;clocks(3)', 'valid=0;en=0;clocks(3)')
    bench=bench.replace('valid=1;clocks(5)', 'valid=1;en=1;clocks(5)')
    (DEST/'tb.sv').write_text(bench)
    lib=DEST.as_posix()+'/sim';log=OUT/'r12_full_system_mapped_lateral.log'
    do=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -work {lib} D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v {DEST.as_posix()}/mapped.v
vlog -sv -work {lib} {DEST.as_posix()}/tb.sv
vsim -c {lib}.tb_sin12_r12_trim
run -all
quit -f
'''
    (DEST/'run.do').write_text(do)
    p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(DEST/'run.do'),'-l',str(log)],cwd=ROOT,capture_output=True,text=True,timeout=120)
    result=log.read_text();assert p.returncode==0 and 'R12_PULSED_FORWARD_REFERENCE_LOW_SPEED_SYMMETRY_PASS' in result and '** Fatal' not in result,p.stdout+p.stderr
    assert verify_current_netlist()==frozen_net_hash,'Synthesis netlist changed during mapped test'
    report=dict(passed=True,hardware_access=False,internal_forces=False,netlist_sha256=hashlib.sha256(net.read_bytes()).hexdigest(),
       scope='actual full-system mapped lateral plus pulsed forward trim, base4/base6, zero wheel feedback, yaw signs/wrap/pauses/owners; actual parent STOP LUT included',
       unconnected_promoted_spin_inputs=unconnected,actual_parent_stop_lut=stop_cell+'\n'+stop_init,spin_path_mapped_validation=False,mapped_wheel_target_bits=wheel_bits,
       parent_invariant='invalid heading_yaw_valid forces interlocked_enable=0 upstream; mapped test uses coherent inputs',
       note='30 spin-only arithmetic input ports intentionally X; all observed lateral outputs must be known and correct. Vendor primitive warnings for unconnected unused ports are expected.')
    (OUT/'SIN12_R12_MAPPED_LATERAL_VALIDATION.json').write_text(json.dumps(report,indent=2))
    print('Actual system mapped lateral trim: both directions/wrap/pause/low-speed PASS; spin-only promoted inputs unconnected')
if __name__=='__main__':main()
