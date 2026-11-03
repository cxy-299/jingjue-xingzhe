"""REVIEW ONLY: prove a smaller temporary trim variable without changing PID."""
from pathlib import Path
import hashlib,json,re,subprocess,difflib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board/r19_trim_width_review'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    source=ROOT/'fpga/motor_bt_drive/chassis_trim.v';before=sha(source)
    text=source.read_text(encoding='utf-8');assert text.count('    integer h;')==1
    candidate=text.replace('    integer h;','    reg signed [9:0] h;')
    OUT.mkdir(exist_ok=False);cp=OUT/'chassis_trim_10bit_candidate.v';cp.write_text(candidate,encoding='utf-8')
    (OUT/'candidate.diff').write_text(''.join(difflib.unified_diff(text.splitlines(True),candidate.splitlines(True),fromfile='production/chassis_trim.v',tofile='review-only/chassis_trim.v')),encoding='utf-8')
    expressions=re.findall(r'^\s*h=([^;]+);',text,re.M);assert len(expressions)==2
    bench='''`timescale 1ns/1ps
module tb_trim_width;
reg signed [16:0] wrapped;
integer value,mode,cap,old_h,old_c,new_c;
reg signed [9:0] new_h;
initial begin
 for(value=-65536;value<=65535;value=value+1)begin
  wrapped=value;
  for(mode=0;mode<2;mode=mode+1)begin
   if(mode==0)begin
'''+f'    old_h={expressions[0]};new_h={expressions[0]};\n'+'''   end else begin
'''+f'    old_h={expressions[1]};new_h={expressions[1]};\n'+'''   end
   if(old_h!=={{22{new_h[9]}},new_h})$fatal(1,"temporary mismatch %d %d",value,mode);
   for(cap=0;cap<=4;cap=cap+1)begin
    old_c=old_h>cap?cap:old_h< -cap?-cap:old_h;
    new_c=$signed(new_h)>cap?cap:$signed(new_h)< -cap?-cap:$signed(new_h);
    if(old_c!==new_c)$fatal(1,"correction mismatch %d %d %d",value,mode,cap);
   end
  end
 end
 $display("R19_TRIM_TEMP_ALL131072_INPUTS_BOTH_FORMULAS_ALL5_CAPS_BIT_EXACT_PASS");$finish;
end
endmodule
'''
    (OUT/'tb_trim_width.sv').write_text(bench)
    lib=(ROOT/'tmp/r19_trim_width_truth').as_posix()
    truth=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -sv -work {lib} {(OUT/'tb_trim_width.sv').as_posix()}
vsim -c {lib}.tb_trim_width
run -all
quit -f
'''
    results=[]
    def run(name,do):
        path=OUT/(name+'.do');path.write_text(do)
        p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(path),'-l',str(OUT/(name+'.log'))],cwd=ROOT/'fpga/motor_bt_drive',capture_output=True,text=True,timeout=120)
        (OUT/(name+'_stdout.log')).write_text(p.stdout);(OUT/(name+'_stderr.log')).write_text(p.stderr)
        log=(OUT/(name+'.log')).read_text();assert p.returncode==0 and '** Fatal' not in log and re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)',log)[-1]==('0','0'),p.stdout[-3000:]+p.stderr
        markers=re.findall(r'^# ([^\r\n]*PASS[^\r\n]*)',log,re.M);assert markers
        results.append(dict(test=name,passed=True,errors=0,warnings=0,markers=markers))
    run('truth',truth)
    for name in ['trim','original_trim','lateral_trim']:
        oldlib='sim_sin12_r13_'+name
        do=(ROOT/'fpga/motor_bt_drive'/('run_modelsim_sin12_r13_'+name+'.do')).read_text(encoding='utf-8')
        # Each existing bench gets a unique library, preserving historical runs.
        matches=re.findall(r'vlog -work (\S+)',do);assert matches
        do=do.replace(matches[0],(ROOT/'tmp'/('r19_trim_width_'+name)).as_posix())
        do=do.replace(' chassis_trim.v',' '+cp.as_posix())
        assert cp.as_posix() in do
        run(name,do)
    assert sha(source)==before
    report=dict(passed=True,review_only=True,production_modified=False,production_sha256=before,
        candidate_sha256=sha(cp),signed17_inputs=131072,formulas=2,correction_caps=[0,1,2,3,4],
        changes='Only temporary integer h32 -> signed10; gains, thresholds, registers, cycles and safety gates unchanged',
        results=results,scope='Exhaustive combinational arithmetic and actual candidate RTL regressions; not routed STA, mapped trim, SDF or physical acceptance',
        authorization='Pending: do not apply across existing source SHA restriction without user instruction')
    (OUT/'PROOF.json').write_text(json.dumps(report,indent=2))
    hashes={p.relative_to(OUT).as_posix():sha(p) for p in OUT.rglob('*') if p.is_file()};(OUT/'SHA256.json').write_text(json.dumps(hashes,indent=2))
    assert all(sha(OUT/n)==v for n,v in hashes.items());print(json.dumps(report,indent=2))
if __name__=='__main__':main()
