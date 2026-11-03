"""Archive the verified R14 offline candidate. Never programs hardware/Pi."""
from pathlib import Path
import hashlib, json, re, shutil

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(name):
    return json.loads((OUT/name).read_text(encoding='utf-8-sig'))

def main():
    manifest=load('sin12_hdmi_r14_build_sources.json')
    software=load('sin12_hdmi_r14_software_sources.json')
    assert len(manifest)==57
    hardware_mismatches=[p for p,h in manifest.items() if sha(ROOT/p)!=h]
    software_mismatches=[p for p,h in software.items() if sha(ROOT/p)!=h]
    assert not hardware_mismatches,hardware_mismatches
    assert not software_mismatches,software_mismatches
    assert (OUT/'sin12_hdmi_r14_build_exit.txt').read_text().strip()=='0'

    timing=load('SIN12_R14_TIMING_INSPECTION_FINAL_2026-10-31.json')
    assert timing['internal_sta_checks_pass'] and all(timing['checks'].values())
    maps={k:load(f'SIN12_R14_MAPPED_{k.upper()}_VALIDATION.json') for k in ('tof','target','recovery')}
    net=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
    net_hash=sha(net)
    assert all(row['passed'] and row['netlist_sha256']==net_hash for row in maps.values())
    assert maps['tof']['checks']==91
    assert maps['target']['vectors']==2172
    rec=maps['recovery']
    assert rec['primitive_count']==2688 and not rec['internal_forces'] and not rec['altered_mapped_constants']
    assert len(rec['scenario_markers'])==5
    rec_log=(OUT/'r14_full_system_mapped_recovery.log').read_text()
    assert 'R14_ACTUAL_MAPPED_RECOVERY_PASS' in rec_log and 'Errors: 0, Warnings: 0' in rec_log

    software_xml=__import__('xml.etree.ElementTree',fromlist=['']).parse(OUT/'r14_software_corrected_20261031.xml').find('testsuite')
    assert software_xml is not None and software_xml.attrib['tests']=='209'
    assert all(software_xml.attrib[k]=='0' for k in ('errors','failures','skipped'))
    tk_first=load('r14_console_validation.json')
    assert len(tk_first['tests'])==94
    tk_failed=[t['test'] for t in tk_first['tests'] if not t['passed']]
    assert len(tk_failed)==1 and not any(t['skipped'] for t in tk_first['tests'])
    retry=__import__('xml.etree.ElementTree',fromlist=['']).parse(OUT/'r14_tk_targeted_retry_20261031.xml').find('testsuite')
    assert retry is not None and retry.attrib['tests']=='1' and all(retry.attrib[k]=='0' for k in ('errors','failures','skipped'))

    impl=ROOT/'fpga/sin12_hdmi/impl'
    pnr=impl/'pnr'
    stamp=__import__('datetime').datetime.fromtimestamp((pnr/'sin12_hdmi_system.fs').stat().st_mtime).strftime('%Y%m%d_%H%M%S')
    archive=OUT/f'sin12_hdmi_r14_{stamp}'
    if archive.exists(): raise FileExistsError(f'Preserve existing archive: {archive}')
    report=dict(candidate='SIN12 R14',archive=str(archive),usercode='534E324E',map_id='2613',
        source_manifest_count=57,hardware_source_mismatches=[],software_source_count=len(software),software_source_mismatches=[],
        netlist_sha256=net_hash,fs_sha256=sha(pnr/'sin12_hdmi_system.fs'),
        internal_sta_checks_pass=True,setup_violations=timing['setup_violations'],hold_violations=timing['hold_violations'],
        clocks=timing['clocks'],fmax_mhz=timing['fmax_mhz'],resources=timing['resources'],
        limitations=timing['limitations'],full_external_timing_signoff=False,
        mapped={k:{key:row.get(key) for key in ('passed','netlist_sha256','checks','vectors','primitive_count','internal_forces','altered_mapped_constants','scenario_markers','scope')}
                for k,row in maps.items()},
        software_tests=dict(tests=int(software_xml.attrib['tests']),passed=int(software_xml.attrib['tests']),failed=0,skipped=0),
        isolated_tk_first_run=dict(tests=94,passed=93,failed=1,skipped=0,failed_test=tk_failed[0]),
        isolated_tk_exact_retry_passed=True,
        hardware_actions=dict(accessed=False,sram_downloaded=False,flash_written=False,motors_or_power_controlled=False),
        current_hardware_baseline='R12 / UserCode 534E324C / K0C',
        pi=dict(candidate_deployed=False,online_version='a4-digit-v3-whitewall-20261031',
                last_readonly_page_observation='older A4 detector page showed digit0 detection at 90.1%, but controlled target not locked; FPGA idle and ToF invalid/0mm hard-stop'),
        recovery_scope='Actual 50MHz mapped primitive cone; true active-low key_s0 input and its mapped reset producer; 2688 primitives; no forced internal state or changed mapped constants. 6500 accelerated external sample_tick strobes test freshness contract, not 65 seconds of wall-clock or routed SDF.',
        note='Offline candidate evidence only. No SRAM/Flash approval, no Pi deployment, no vehicle pass. MPW, PR1014 ordinary PCLK, external DVP and HDMI text OSD remain open.')

    archive.mkdir()
    shutil.copytree(impl,archive/'impl')
    selected=set(manifest)|set(software)|{'scripts/freeze_sin12_r14.py','scripts/inspect_sin12_r14_timing.py','scripts/archive_sin12_r14.py'}
    validation_hashes={}
    for name in sorted(selected):
        source=ROOT/name
        dest=archive/'sources'/name
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,dest)
        assert sha(source)==sha(dest)
        validation_hashes[name]=sha(source)
    report['validation_and_source_hashes']=validation_hashes

    evidence_patterns=['*R14*.json','*R14*.md','r14_*.log','r14_*.json','r14_*.xml','sin12_hdmi_r14_*','r14_*.jpg','r14_*.tar']
    for pattern in evidence_patterns:
        for source in OUT.glob(pattern):
            if source.is_file(): shutil.copy2(source,archive/source.name)
    for folder in ('sin12_r14_mapped_tof','sin12_r14_mapped_target','sin12_r14_mapped_recovery'):
        source=ROOT/'tmp'/folder
        if source.exists(): shutil.copytree(source,archive/'mapped_wrappers'/folder)
    (archive/'BUILD_VERIFICATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'SIN12_R14_BUILD_VERIFICATION_2026-10-31.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    inventory={str(p.relative_to(archive)).replace('\\','/'):sha(p) for p in archive.rglob('*') if p.is_file()}
    (archive/'ARCHIVE_SHA256.json').write_text(json.dumps(inventory,indent=2),encoding='utf-8')
    assert all(sha(archive/p)==h for p,h in inventory.items())
    print(json.dumps(dict(archive=str(archive),files=len(inventory),fs_sha256=report['fs_sha256'],hardware_access=False),indent=2))

if __name__=='__main__': main()
