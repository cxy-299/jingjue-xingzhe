"""Seal only a genuinely passed, quiescent, independently archived R19 build."""
from pathlib import Path
from datetime import datetime
import hashlib,json,re,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def verify_archive(folder):
    manifest=read(folder/'SHA256.json')
    assert all(sha(folder/n)==v for n,v in manifest.items()),str(folder)
    return dict(path=folder.relative_to(ROOT).as_posix(),files=len(manifest),sha256_manifest=sha(folder/'SHA256.json'))
def main():
    sta=read(OUT/'SIN12_R19_TIMING_INSPECTION_2026-11-01.json');audit=read(OUT/'SIN12_R19_CONSTRAINT_AUDIT.json')
    assert sta['internal_sta_checks_pass'] and all(sta['checks'].values()) and audit['passed']
    net=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg';digest=sha(net)
    reports={k:read(OUT/f'SIN12_R19_MAPPED_{k}_VALIDATION.json') for k in ('TOF','TARGET','NAV')}
    assert all(r['passed'] and r.get('netlist_sha256',r.get('full_system_netlist_sha256'))==digest for r in reports.values())
    tests=read(OUT/'R19_TEST_VALIDATION.json');assert tests['passed'] and all(sha(ROOT/n)==v for n,v in tests['files'].items())
    preserved=[verify_archive(OUT/'sin12_hdmi_r18_20261101_203535'),verify_archive(OUT/'task5_digit_to_tof_20261101')]
    # The archive program repeats the complete source/STA/constraint/mapped
    # binding checks before creating the independent snapshot.
    p=subprocess.run([sys.executable,str(ROOT/'scripts/archive_sin12_r19.py')],cwd=ROOT,capture_output=True,text=True)
    assert p.returncode==0,p.stdout+p.stderr
    created=json.loads(p.stdout.strip().splitlines()[-1]);assert created['passed']
    dest=Path(created['archive']).resolve();assert dest.parent==OUT.resolve()
    verify_archive(dest)
    probe=r'''$r19ProbePid=$PID
$r19Pending=@(Get-CimInstance Win32_Process | Where-Object {
 $_.ProcessId -ne $r19ProbePid -and (
 $_.Name -match '^(gw_sh|gw_syn|gw_pnr|pnr|synthesize|vsim|vsimk|vopt|vlog)\.exe$' -or
 ($_.Name -match '^python(w)?\.exe$' -and $_.CommandLine -match 'verify_sin12_r19_|test_sin12_r19_|prepare_r19_') -or
 ($_.Name -match '^pwsh\.exe$' -and $_.CommandLine -match 'build_sin12_r19.ps1'))
} | Select-Object ProcessId,Name,CreationDate)
ConvertTo-Json -InputObject $r19Pending -Compress'''
    q=subprocess.run([shutil.which('pwsh'),'-NoProfile','-Command',probe],capture_output=True,text=True)
    assert q.returncode==0,q.stderr
    pending=json.loads(q.stdout);assert not pending,('Validation background still active',pending)
    hardware=read(OUT/'sin12_hdmi_r19_build_sources.json');software=read(OUT/'sin12_hdmi_r19_software_sources.json')
    assert len(hardware)==58 and all(sha(ROOT/n)==v for n,v in {**hardware,**software}.items())
    verification=read(dest/'BUILD_VERIFICATION.json');assert verification['passed']
    now=datetime.now().isoformat();tables=sta['tables']
    result=dict(passed=True,completed_local=now,revision='R19/K13/REV5_ENABLE15',user_code='534E3253',
        scope='Offline candidate validation and independent archive; not downloaded or physical acceptance',
        hardware_sources=len(hardware),software_sources=len(software),netlist_sha256=digest,
        fs_sha256=sha(ROOT/'fpga/sin12_hdmi/impl/pnr/sin12_hdmi_system.fs'),
        independent_archive=str(dest),background_pending=[],preserved_archives=preserved,
        setup_violations=sta['setup_violations'],hold_violations=sta['hold_violations'],
        minimum_setup_ns=tables['3.1.1 Setup Paths Table']['minimum_slack_ns'],
        minimum_hold_ns=tables['3.1.2 Hold Paths Table']['minimum_slack_ns'],fmax_mhz=sta['fmax_mhz'],
        serializer_recovery_ns=tables['3.1.3.1 Recovery Paths Table[1]']['minimum_slack_ns'],
        serializer_removal_ns=tables['3.1.4.1 Removal Paths Table[1]']['minimum_slack_ns'],
        global_recovery_ns=tables['3.1.3.2 Recovery Paths Table[2]']['minimum_slack_ns'],
        global_removal_ns=tables['3.1.4.2 Removal Paths Table[2]']['minimum_slack_ns'],
        constraints=audit['process_config'],resources=sta['resources'],mapped_primitive_count=reports['NAV']['primitive_count'],
        mapped_warnings=reports['NAV']['final_warnings'],mapped_errors=reports['NAV']['final_errors'],
        tests=dict(unit=tests['unit_tests'],isolated_tk=tests['isolated_gui_tests'],additional_task5_gui=tests['task5_additional_gui_regressions'],
                   rtl_scenarios=tests['new_rtl_scenarios'],authorized_width_regression_groups=tests['production_width_regression_groups']),
        approved_source_changes=tests['authorized_equivalent_source_changes'],
        programmed=False,flash_written=False,vehicle_tested=False,whole_system_sdf=False,
        limitations=verification['limitations']+sta['limitations'],failure_history_preserved=True)
    handoff=f'''# SIN12 R19 FINAL HANDOFF

离线核验和独立归档完成，时间{now}。未下载SRAM/Flash，未进行实车或整机SDF验收。

- 身份R19/UserCode534E3253/K13/REV5_ENABLE15/map2613；左1/前3逐格/右1/恢复原航向继续原终点，500名义计数100mm。
- STA 16项全部通过，六时钟零TNS、setup0/hold0；控制Fmax{sta['fmax_mhz']['clk_50m']}MHz，setup最差+{result['minimum_setup_ns']:.3f}ns，hold+{result['minimum_hold_ns']:.3f}ns。
- OSER四真实RESET端点rec/rem各12路径；全局rec/rem各200路径。16有效约束、两pixel CLEAR恰2端点、下游CLEAR/BSRAM RESET受检，原50/PCLK75.002/raw375/DHCEserial375/pixel75/XCLK25及RESET16/15/DHCE CEN等窄例外不改。
- 同一新VG实际ToF91/target2172/nav{reports['NAV']['primitive_count']}全部PASS；导航Errors0/Warnings{reports['NAV']['final_warnings']}（如有均官方SDPX9B既有警告）。真实北/西/南五MOVE、短近障锁存、正确测点/场外FF、二障碍安全停保留终点通过。
- {tests['unit_tests']}软件/{tests['isolated_gui_tests']}隔离Tk0skip/额外2任务5GUI/{tests['new_rtl_scenarios']}RTL及7组当前生产回归已过。两处类型位宽变化为用户明确授权，原/新SHA与等价穷举留证；参数、PID增益、周期、寄存器和实时安全门不改。
- 当前{len(hardware)}硬件源/{len(software)}软件源、完整impl、当前wrapper/bench/source SHA及全部成功失败日志独立封存。归档：{dest.name}；VG SHA256 {digest}。
- 已检查无核验后台待查；R18和任务5独立旧归档逐文件SHA重开复验。R17/R16/R15/R12及全部历史失败保留，不声称当前硬件版本读回。

边界：500/100mm未新地面标定，22cm车宽侧移10cm不保证任意绕开；210膨胀400预停100硬停/速度4/容差/最多8次等保护保持，占用reason14停不得清图强过。GUI只用新鲜匹配K13及新replan代次绘测点；任务5数字转ToF和Pi v4保留。外部IO无delay预算、MPW覆盖、PR1014普通PCLK及HDMI字幕仍未签核；mapped外部plant/ticks缩放，速度4仅已披露RTL/fullUART范围。无串口、电机电源、Pi或GUI重启操作。
'''
    (OUT/'R19_VALIDATION.json').write_text(json.dumps(result,indent=2))
    (OUT/'R19_FINAL_HANDOFF.md').write_text(handoff,encoding='utf-8')
    maintenance=OUT/'SIN12_R19_LEFT_THREE_MAP_MAINTENANCE_2026-11-01.md'
    with maintenance.open('a',encoding='utf-8') as f:
        f.write(f'\n## {now} 最终离线核验与独立归档完成\n\n第九轮真实STA16项/约束审计/同VG三类映射/当前生产回归全部通过；setup0/hold0、Fmax{result["fmax_mhz"]["clk_50m"]}MHz、setup+{result["minimum_setup_ns"]:.3f}ns、hold+{result["minimum_hold_ns"]:.3f}ns。完整独立归档{dest.name}，58硬件/{len(software)}软件及当前全部证据封存；R19_VALIDATION.json/R19_FINAL_HANDOFF.md已更新。已确认无核验后台待查；后续重开SHA复验成功后可删除此临时监控。未下载硬件、未实车或整机SDF验收；所有既有边界和历史失败保持。\n')
    for name in ['R19_VALIDATION.json','R19_FINAL_HANDOFF.md',maintenance.name]:
        shutil.copy2(OUT/name,dest/'evidence'/name)
    verification.update(final_validation=result,final_handoff='evidence/R19_FINAL_HANDOFF.md')
    (dest/'BUILD_VERIFICATION.json').write_text(json.dumps(verification,indent=2))
    hashes={p.relative_to(dest).as_posix():sha(p) for p in sorted(dest.rglob('*')) if p.is_file() and p.name!='SHA256.json'}
    # Nested history SHA256 manifests are evidence too; exclude only the root.
    for p in dest.rglob('SHA256.json'):
        if p!=dest/'SHA256.json':hashes[p.relative_to(dest).as_posix()]=sha(p)
    (dest/'SHA256.json').write_text(json.dumps(hashes,indent=2))
    sealed=verify_archive(dest)
    print(json.dumps(dict(passed=True,archive=str(dest),files=sealed['files'],sha256_manifest=sealed['sha256_manifest'],background_pending=0,validation=str(OUT/'R19_VALIDATION.json'),handoff=str(OUT/'R19_FINAL_HANDOFF.md'))))
if __name__=='__main__':main()
