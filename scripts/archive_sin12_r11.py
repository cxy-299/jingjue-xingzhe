"""Archive verified offline R11 candidate. No programmer or serial access."""
from pathlib import Path
import datetime,hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def read(name):return json.loads((OUT/name).read_text(encoding='utf-8-sig'))
def main():
    timing=read('SIN12_R11_TIMING_INSPECTION_2026-10-30.json')
    assert timing['internal_sta_checks_pass'] and all(timing['checks'].values())
    manifest=read('sin12_hdmi_r11_build_sources.json')
    assert len(manifest)==57 and all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in manifest.items())
    software=read('sin12_hdmi_r11_software_sources.json')
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in software.items())
    validation=read('SIN12_R11_OFFLINE_VALIDATION_2026-10-30.json')
    assert validation['rtl_all_passed'] and validation['tk_all_passed'] and validation['tk_passed']==82 and validation['tk_skipped']==0
    assert '38 passed' in (OUT/'r11_python_contracts.log').read_text()
    netlist=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
    net_hash=hashlib.sha256(netlist.read_bytes()).hexdigest()
    mapped={key:read(f'SIN12_R11_MAPPED_{key.upper()}_VALIDATION.json') for key in ('tof','target','approach','lateral')}
    assert all(m['passed'] and m['netlist_sha256']==net_hash for m in mapped.values())
    assert mapped['tof']['checks']==91 and mapped['target']['vectors']==2172 and mapped['approach']['samples']==5000
    impl=ROOT/'fpga/sin12_hdmi/impl';pnr=impl/'pnr'
    tr=(pnr/'sin12_hdmi_system.tr').read_text()
    rpt=(pnr/'sin12_hdmi_system.rpt.txt').read_text()
    assert len(re.findall(r'^\s+TC_\w+\s+Actived',tr,re.M))==16
    assert '-replicate' in (pnr/'cmd.do').read_text() and 'gowin_replicate' in tr
    assert re.search(r'--OSER10\s*\|\s*4',rpt)
    sdc=(ROOT/'fpga/sin12_hdmi/sin12_hdmi_system.sdc').read_text()
    assert sdc.count('set_false_path')==2 and sdc.count('set_multicycle_path')==2
    assert 'pixel_release_meta*/CLEAR u_camera/pixel_release_sync*/CLEAR' in sdc
    gate=netlist.read_text()
    resets=re.findall(r'DFFCE (pixel_release_(?:meta|sync)_s\d+)\s*\(([\s\S]*?)\);',gate)
    assert len(resets)==2
    assert any('.D(pixel_release_meta)' in body for name,body in resets if 'sync' in name)
    config=json.loads((impl/'sin12_hdmi_system_process_config.json').read_text(encoding='utf-8-sig'))
    stamp=datetime.datetime.fromisoformat(timing['files']['sin12_hdmi_system.fs']['modified_local']).strftime('%Y%m%d_%H%M%S')
    archive=OUT/f'sin12_hdmi_r11_{stamp}';assert not archive.exists(), 'Do not overwrite an immutable candidate'
    fs_hash=hashlib.sha256((pnr/'sin12_hdmi_system.fs').read_bytes()).hexdigest()
    report=dict(timing,archive=str(archive),map_id='2613',internal_sta_pass=True,
                sram_tested=False,flash_approved=False,fs_sha256=fs_hash,
                setup_min_ns=timing['tables']['3.1.1 Setup Paths Table']['minimum_slack_ns'],
                hold_min_ns=timing['tables']['3.1.2 Hold Paths Table']['minimum_slack_ns'],
                options={k:config[k] for k in ('Route_Option','Run_Timing_Driven','Replicate_Resources','SSPI','JTAG','MSPI','USERCODE')},
                mapped_tof=mapped['tof'],mapped_target=mapped['target'],mapped_approach=mapped['approach'],mapped_lateral=mapped['lateral'],
                sdc_constraints_active=16,pixel_reset_synchronizer_cells=resets,
                first_path_statistics_logic_levels=int(re.search(r'Logic Level\s*[:=]\s*(\d+)',tr)[1]) if re.search(r'Logic Level\s*[:=]\s*(\d+)',tr) else None,
                note='Internal timing and scoped mapped functionality verified; no full routed SDF/vehicle/external IO signoff. Estimated position is not an absolute position sensor.')
    validation.update(internal_build_validation_complete=True,whole_system_routed_validation_pending=False,full_routed_functional_signoff=False)
    (OUT/'SIN12_R11_OFFLINE_VALIDATION_2026-10-30.json').write_text(json.dumps(validation,ensure_ascii=False,indent=2),encoding='utf-8')
    archive.mkdir();shutil.copytree(impl,archive/'impl')
    for name in set(manifest)|set(software):
        p=archive/'sources'/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,p)
    for name in list((ROOT/'fpga/motor_bt_drive').glob('*r11*'))+list((ROOT/'scripts').glob('*r11*')):
        if name.is_file():
            p=archive/'sources'/name.relative_to(ROOT);p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(name,p)
    for pattern in ('*R11*.json','*R11*.md','r11_*.log','r11_*.json','sin12_hdmi_r11_*','sin12_fixed_console_validation.*'):
        for name in OUT.glob(pattern):
            if name.is_file():shutil.copy2(name,archive/name.name)
    for directory in ['sin12_r11_system_tof','sin12_r11_system_target','sin12_r11_mapped_approach','sin12_r11_mapped_lateral']:
        source=ROOT/'tmp'/directory
        if source.exists():
            dest=archive/'mapped_wrappers'/directory;dest.mkdir(parents=True)
            for p in source.iterdir():
                if p.is_file() and p.suffix in ('.v','.sv','.do'):shutil.copy2(p,dest/p.name)
    (archive/'BUILD_VERIFICATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'SIN12_R11_BUILD_VERIFICATION_2026-10-30.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    program=(ROOT/'scripts/program_sin12_r9_sram.ps1').read_text(encoding='utf-8')
    program=program.replace('r9','r11').replace('R9','R11').replace('534E3249','534E324B').replace('534[Ee]3249','534[Ee]324B')
    program=program.replace('sin12_hdmi_r11_20261030_135330',archive.name).replace("-ne 56", "-ne 57")
    program=program.replace('9EB3E89E8B4D4002BB4493AA3C865CA0095F639A2ABA2C08B5568E22B0BFC0DB',fs_hash.upper())
    program=program.replace('if ($ValidateFiles)',"if ($r11Validation.mapped_lateral.passed -ne $true) { throw 'R11 actual mapped lateral evidence missing.' }\nif ($ValidateFiles)")
    (ROOT/'scripts/program_sin12_r11_sram.ps1').write_text(program,encoding='utf-8')
    shutil.copy2(ROOT/'scripts/program_sin12_r11_sram.ps1',archive/'sources/scripts/program_sin12_r11_sram.ps1')
    print(json.dumps(dict(archive=str(archive),fs_sha256=fs_hash,netlist_sha256=net_hash,hardware_access=False),indent=2))
if __name__=='__main__':main()
