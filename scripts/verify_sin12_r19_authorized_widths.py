"""Run existing safety regressions on the two expressly approved source bytes."""
from pathlib import Path
import hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board';BASE=ROOT/'fpga/motor_bt_drive'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    approval=json.loads((OUT/'R19_PROTECTED_SOURCE_CHANGE_REQUEST.json').read_text())
    assert approval['status']=='applied_authorized_equivalent_changes' and approval['production_applied']
    assert approval['explicit_user_answer']=='允许这两处等价修改（推荐）'
    assert len(approval['requests'])==2
    for r in approval['requests']:assert sha(ROOT/r['source'])==r['candidate_sha256']
    specs=[('two_stage','run_modelsim_sin12_r17_two_stage.do','SIN12_R17_TWO_STAGE_ALL_PASS'),
      ('recovery','run_modelsim_sin12_r14_target_recovery.do','SIN12_R14_TARGET_RECOVERY_ALL_PASS'),
      ('settle','run_modelsim_sin12_r16_reacquire_settle.do','SIN12_R16_REACQUIRE_SEARCH_ALL_PASS'),
      ('trim','run_modelsim_sin12_r13_trim.do','R12_PULSED_FORWARD_REFERENCE_LOW_SPEED_SYMMETRY_PASS'),
      ('original_trim','run_modelsim_sin12_r13_original_trim.do','R4_HEADING_FORWARD_REVERSE_WRAP_OWNER_SPIN_TRANSLATION_PASS'),
      ('lateral_trim','run_modelsim_sin12_r13_lateral_trim.do','R10_LATERAL_LEFT_RIGHT_SIGN_WRAP_PAUSE_OWNER_LOW_SPEED_PASS'),
      ('full_uart','run_modelsim_sin12_r19_full.do','SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS')]
    results=[];files={}
    for name,template,marker in specs:
        text=(BASE/template).read_text(encoding='utf-8')
        lib=re.search(r'vlog(?: -sv)? -work (\S+)',text)[1]
        text=text.replace(lib,(ROOT/'tmp'/('sin12_r19_ninth_'+name)).as_posix())
        do=OUT/('r19_ninth_'+name+'.do');do.write_text(text)
        log=OUT/('r19_ninth_'+name+'.log')
        p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(do),'-l',str(log)],cwd=BASE,capture_output=True,text=True,timeout=180)
        (OUT/('r19_ninth_'+name+'_stdout.log')).write_text(p.stdout)
        (OUT/('r19_ninth_'+name+'_stderr.log')).write_text(p.stderr)
        content=log.read_text()
        assert p.returncode==0 and marker in content and '** Fatal' not in content and re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)',content)[-1]==('0','0'),p.stdout[-3000:]+p.stderr
        markers=re.findall(r'^# ([^\r\n]*PASS[^\r\n]*)',content,re.M)
        results.append(dict(test=name,passed=True,errors=0,warnings=0,markers=markers))
        for path in [BASE/template,do,log]:files[path.relative_to(ROOT).as_posix()]=sha(path)
        for token in text.split():
            if token.endswith(('.v','.sv')):
                src=Path(token);src=src if src.is_absolute() else BASE/src
                files[src.resolve().relative_to(ROOT).as_posix()]=sha(src)
        print(name,'actual production regression PASS',flush=True)
    for r in approval['requests']:assert sha(ROOT/r['source'])==r['candidate_sha256']
    report=dict(passed=True,hardware_access=False,vehicle_tested=False,full_system_sdf=False,production_sources=True,
        approval_sha256=sha(OUT/'R19_PROTECTED_SOURCE_CHANGE_REQUEST.json'),
        approved_source_hashes={r['source']:r['candidate_sha256'] for r in approval['requests']},results=results,files=files,
        limitations='RTL benches include scaled clocks and sensor fixtures; not mapped or physical acceptance')
    (OUT/'R19_AUTHORIZED_WIDTH_RTL_VALIDATION.json').write_text(json.dumps(report,indent=2))
    print('All7 actual production regression groups PASS; no STA claim')
if __name__=='__main__':main()
