"""Immutable offline R13 evidence archive; NO programmer/serial/Pi operations."""
from pathlib import Path
import datetime,hashlib,json,re,shutil,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(n):return json.loads((OUT/n).read_text(encoding='utf-8-sig'))
def main():
    timing=read('SIN12_R13_TIMING_INSPECTION_2026-10-30.json')
    assert timing['internal_sta_checks_pass'] and all(timing['checks'].values())
    manifest=read('sin12_hdmi_r13_build_sources.json');software=read('sin12_hdmi_r13_software_sources.json')
    assert len(manifest)==57 and all(sha(ROOT/p)==h for p,h in manifest.items())
    assert all(sha(ROOT/p)==h for p,h in software.items())
    impl=ROOT/'fpga/sin12_hdmi/impl';pnr=impl/'pnr';netlist=impl/'gwsynthesis/sin12_hdmi_system.vg'
    net_hash=sha(netlist)
    mapped={k:read(f'SIN12_R13_MAPPED_{k.upper()}_VALIDATION.json') for k in ['tof','target','approach','lateral','recovery']}
    assert all(m['passed'] and m['netlist_sha256']==net_hash for m in mapped.values())
    assert mapped['tof']['checks']==91 and mapped['target']['vectors']==2172 and mapped['approach']['samples']==5000
    assert mapped['recovery']['primitive_count']==2722 and not mapped['recovery']['internal_forces']
    assert not mapped['recovery']['altered_mapped_constants'] and mapped['recovery']['lut_independence_proofs']
    recovery_log=(OUT/'r13_full_system_mapped_recovery.log').read_text()
    assert 'R13_ACTUAL_MAPPED_RECOVERY_PASS' in recovery_log and 'Errors: 0, Warnings: 0' in recovery_log
    assert sha(ROOT/'tmp/sin12_r13_mapped_recovery/mapped.v')==mapped['recovery']['mapped_wrapper_sha256']
    for name,info in timing['files'].items():assert sha(pnr/name)==info['sha256'],name
    assert (OUT/'sin12_hdmi_r13_build_exit.txt').read_text().strip()=='0'
    tr=(pnr/'sin12_hdmi_system.tr').read_text();rpt=(pnr/'sin12_hdmi_system.rpt.txt').read_text()
    assert len(re.findall(r'^\s+TC_\w+\s+Actived',tr,re.M))==16
    assert '-replicate' in (pnr/'cmd.do').read_text() and 'gowin_replicate' in tr
    assert re.search(r'--OSER10\s*\|\s*4',rpt)
    sdc=(ROOT/'fpga/sin12_hdmi/sin12_hdmi_system.sdc').read_text()
    assert sdc.count('set_false_path')==2 and sdc.count('set_multicycle_path')==2
    assert 'pixel_release_meta*/CLEAR u_camera/pixel_release_sync*/CLEAR' in sdc
    resets=re.findall(r'DFFCE (pixel_release_(?:meta|sync)_s\d+)\s*\(([\s\S]*?)\);',netlist.read_text())
    assert len(resets)==2 and any('.D(pixel_release_meta)' in b for n,b in resets if 'sync' in n)
    config=json.loads((impl/'sin12_hdmi_system_process_config.json').read_text(encoding='utf-8-sig'))
    markers={
      'r13_target_recovery_rtl.log':'SIN12_R13_TARGET_RECOVERY_ALL_PASS',
      'r13_wait_telemetry.log':'R13_REAL_UART_J_ACTIVE_S10_ORIGINAL_ID_AND_K0D_PASS',
      'r13_full.log':'SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS'}
    for filename,marker in markers.items():
        text=(OUT/filename).read_text();assert marker in text and '** Fatal' not in text,filename
    for filename in ['r13_alignment_plant.log','r13_lateral_trim.log','r13_trim.log','r13_original_trim.log','r13_legacy_mission.log','r13_legacy_motor_mission.log','r13_map_nav.log','r13_legacy_r12_refine.log','r13_telemetry.log']:
        text=(OUT/filename).read_text();assert 'PASS' in text and '** Fatal' not in text,filename
    py=ET.parse(OUT/'r13_python_contracts.xml').find('testsuite')
    assert py.attrib['tests']=='24' and all(py.attrib[k]=='0' for k in ['errors','failures','skipped'])
    tk=read('r13_console_validation.json');cases=tk['tests']
    assert len(cases)==94 and sum(c['passed'] for c in cases)==93 and not any(c['skipped'] for c in cases)
    failed=[c['test'] for c in cases if not c['passed']]
    assert len(failed)==1 and 'test_local_completion_preserves_permission_but_unchecking_stops' in failed[0]
    retry=ET.parse(OUT/'r13_tk_single_retry.xml').find('testsuite')
    assert retry.attrib['tests']=='1' and all(retry.attrib[k]=='0' for k in ['errors','failures','skipped'])
    stamp=datetime.datetime.fromisoformat(timing['files']['sin12_hdmi_system.fs']['modified_local']).strftime('%Y%m%d_%H%M%S')
    archive=OUT/f'sin12_hdmi_r13_{stamp}';assert not archive.exists(),'Never overwrite an archived candidate'
    report=dict(timing,archive=str(archive),map_id='2613',netlist_sha256=net_hash,
      fs_sha256=sha(pnr/'sin12_hdmi_system.fs'),scoped_offline_validation_complete=True,
      sram_tested=False,flash_approved=False,vehicle_passed=False,full_routed_functional_signoff=False,
      current_hardware_baseline='R12 / 534E324C / K0C',mapped=mapped,
      options={k:config[k] for k in ['Route_Option','Run_Timing_Driven','Replicate_Resources','SSPI','JTAG','MSPI','USERCODE']},
      python_passed=24,tk_first_run=dict(passed=93,failed=1,skipped=0,failed_tests=failed),tk_exact_retry_passed=True,
      recovery_scope='actual mapped primitives at 50MHz; real150ms neutral; same-ID pause/two-new-confirmations/resume; final400-tick expiry uses accelerated EXTERNAL sample_tick, not elapsed4sec; other owners inactive with recorded LUT cofactor independence proofs and unobserved inputs X; no forced nodes or altered constants; NOT full-chip routed SDF',
      lateral_scope='mapped lateral/short-step only;30 promoted spin-only ports X, not spin proof',
      note='First Tk failure preserved, exact retry passed. Old MPW/PCLK/external-DVP/OSD gaps preserved. No hardware action authorized or performed.')
    (OUT/'SIN12_R13_OFFLINE_VALIDATION_2026-10-30.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    archive.mkdir();shutil.copytree(impl,archive/'impl')
    selected=set(manifest)|set(software)|{'scripts/mapped_cone.py'}
    for folder in ['scripts','fpga/motor_bt_drive','tests']:
        selected|={str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/folder).glob('*r13*') if p.is_file()}
    validation_hashes={}
    for name in sorted(selected):
        source=ROOT/name;dest=archive/'sources'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
        assert sha(source)==sha(dest);validation_hashes[name]=sha(source)
    report['validation_and_source_hashes']=validation_hashes
    for pattern in ['*R13*.json','*R13*.md','r13_*.log','r13_*.json','r13_*.xml','sin12_hdmi_r13_*']:
        for source in OUT.glob(pattern):
            if source.is_file():shutil.copy2(source,archive/source.name)
    for source in (ROOT/'tmp').iterdir():
        if not source.is_dir() or 'r13' not in source.name:continue
        for p in source.iterdir():
            if p.is_file() and p.suffix in ['.v','.sv','.do','.json']:
                dest=archive/'mapped_wrappers'/source.name/p.name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
    (archive/'BUILD_VERIFICATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'SIN12_R13_BUILD_VERIFICATION_2026-10-30.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    inventory={str(p.relative_to(archive)).replace('\\','/'):sha(p) for p in archive.rglob('*') if p.is_file()}
    (archive/'ARCHIVE_SHA256.json').write_text(json.dumps(inventory,indent=2))
    assert all(sha(archive/p)==h for p,h in inventory.items())
    print(json.dumps(dict(archive=str(archive),files=len(inventory),fs_sha256=report['fs_sha256'],hardware_access=False),indent=2))
if __name__=='__main__':main()
