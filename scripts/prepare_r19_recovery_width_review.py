"""Prepare a REVIEW-ONLY mission arithmetic candidate; production stays intact."""
from pathlib import Path
import hashlib,json,re,subprocess,difflib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board/r19_recovery_width_review'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    source=ROOT/'fpga/motor_bt_drive/vision_mission_guard.v';before=sha(source)
    text=source.read_text();old='function signed [15:0] wrap_heading(input signed [31:0] value);'
    new='function signed [15:0] wrap_heading(input signed [16:0] value);'
    assert text.count(old)==1 and text.count('=wrap_heading(')==3
    candidate=text.replace(old,new)
    OUT.mkdir(exist_ok=False)
    (OUT/'vision_mission_guard_17bit_candidate.v').write_text(candidate)
    diff=''.join(difflib.unified_diff(text.splitlines(True),candidate.splitlines(True),
        fromfile='production/vision_mission_guard.v',tofile='review-only/vision_mission_guard.v'))
    (OUT/'candidate.diff').write_text(diff)
    function=re.search(r'    function signed \[15:0\] wrap_heading\([\s\S]*?    endfunction',text)[0]
    legacy=function.replace('wrap_heading','wrap_legacy')
    narrow=function.replace('wrap_heading','wrap_narrow').replace('[31:0] value','[16:0] value')
    bench='''`timescale 1ns/1ps
module tb_r19_recovery_width;
'''+legacy+'\n'+narrow+'''
integer value;
initial begin
 for(value=-65536;value<=65535;value=value+1)
   if(wrap_legacy(value)!==wrap_narrow(value))$fatal(1,"width mismatch at %d",value);
 $display("R19_RECOVERY_WRAP_EXHAUSTIVE_131072_VALUES_BIT_EXACT_PASS");$finish;
end
endmodule
'''
    (OUT/'tb_width.sv').write_text(bench)
    lib=(ROOT/'tmp/r19_recovery_width_review').as_posix()
    do=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -sv -work {lib} {(OUT/'tb_width.sv').as_posix()}
vsim -c {lib}.tb_r19_recovery_width
run -all
quit -f
'''
    (OUT/'run.do').write_text(do)
    p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(OUT/'run.do'),'-l',str(OUT/'proof.log')],
        cwd=ROOT,capture_output=True,text=True,timeout=60)
    (OUT/'stdout.log').write_text(p.stdout);(OUT/'stderr.log').write_text(p.stderr)
    log=(OUT/'proof.log').read_text();assert p.returncode==0 and 'EXHAUSTIVE_131072_VALUES_BIT_EXACT_PASS' in log
    assert re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)',log)[-1]==('0','0')
    assert sha(source)==before,'Production must NOT be modified by this review'
    report=dict(passed=True,review_only=True,production_modified=False,production_sha256=before,
        candidate_sha256=sha(OUT/'vision_mission_guard_17bit_candidate.v'),exhaustive_signed17_values=131072,
        call_input_bounds={'origin16_plus_or_minus429':[-33197,33196],
                           'goal16_minus_yaw16':[-65535,65535],'yaw16_minus_origin16':[-65535,65535]},
        proof_scope='Both exact source functions exhaustively equal on ALL signed17 inputs; each of3 actual callers fits this domain',
        not_proven=['No whole mission sequential regression yet','No new synthesis or timing evidence yet','No mapped full mission evidence yet'],
        changes='Only wrap_heading input width32->17; no register, threshold, command or timing-window change',
        authorization='Pending: existing user requirement preserves mission source SHA; do not apply without a new instruction')
    (OUT/'PROOF.json').write_text(json.dumps(report,indent=2))
    hashes={p.relative_to(OUT).as_posix():sha(p) for p in OUT.rglob('*') if p.is_file()}
    (OUT/'SHA256.json').write_text(json.dumps(hashes,indent=2))
    assert all(sha(OUT/n)==v for n,v in hashes.items())
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
