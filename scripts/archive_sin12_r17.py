"""Independently verify/archive R17 evidence; refuses incomplete reports. No hardware I/O."""
from pathlib import Path
from datetime import datetime
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(n):return json.loads((OUT/n).read_text(encoding='utf-8-sig'))
def manifest(m):
    bad=[p for p,h in m.items() if sha(ROOT/p)!=h]
    assert not bad,bad
def main():
    hw=load('sin12_hdmi_r17_build_sources.json');sw=load('sin12_hdmi_r17_software_sources.json')
    assert len(hw)==58
    manifest(hw);manifest(sw)
    assert (OUT/'sin12_hdmi_r17_build_exit.txt').read_text().strip()=='0'
    sta=load('SIN12_R17_TIMING_INSPECTION_2026-11-01.json')
    assert all(sta['checks'].values()) and sta['setup_violations']==sta['hold_violations']==0
    impl=ROOT/'fpga/sin12_hdmi/impl';pnr=impl/'pnr';net=impl/'gwsynthesis/sin12_hdmi_system.vg';nh=sha(net)
    for n,r in sta['files'].items():assert sha(pnr/n)==r['sha256'],n
    audit=load('SIN12_R17_CONSTRAINT_AUDIT.json')
    assert audit['passed'] and audit['netlist_sha256']==nh
    assert len(audit['active_constraints'])==16
    maps={k:load('SIN12_R17_MAPPED_'+s+'_VALIDATION.json') for k,s in
          [('tof','TOF'),('target','TARGET'),('recovery','RECOVERY_SEARCH'),('settle','SETTLE'),('nav','NAV'),('two_stage','TWO_STAGE')]}
    for k,r in maps.items():
        assert r['passed'] and r['netlist_sha256']==nh and not r['internal_forces'],k
    assert maps['tof']['checks']==91 and maps['target']['vectors']==2172
    mapped_warning_summary={}
    for k,folder,bench,log in [
      ('recovery','sin12_r17_mapped_recovery','tb_sin12_r17_mapped_recovery.sv','r17_full_system_mapped_recovery_validation.log'),
      ('settle','sin12_r17_mapped_recovery','tb_sin12_r17_mapped_settle.sv','r17_full_system_mapped_settle_validation.log'),
      ('nav','sin12_r17_mapped_nav','tb_sin12_r17_mapped_nav.sv','r17_full_system_mapped_nav_validation.log'),
      ('two_stage','sin12_r17_mapped_recovery','tb_sin12_r17_mapped_two_stage.sv','r17_full_system_mapped_two_stage_validation.log')]:
        r=maps[k];assert sha(ROOT/'tmp'/folder/'mapped.v')==r['mapped_wrapper_sha256']
        assert sha(ROOT/'fpga/motor_bt_drive'/bench)==r['testbench_sha256']
        text=(OUT/log).read_text()
        summaries=re.findall(r'Errors: (\d+), Warnings: (\d+)',text)
        assert summaries and summaries[-1][0]=='0' and '** Fatal' not in text,log
        warnings=[line for line in text.splitlines() if '** Warning:' in line]
        if k=='nav':
            # Official SDPX9B width9 emits these four unused width18/36-branch
            # warnings. Preserve them; reject any different/new diagnostic.
            assert summaries[-1][1] in ('0','4') and len(warnings)==int(summaries[-1][1]),warnings
            if warnings:
                assert all('prim_sim.v('+str(line)+'): (vopt-2697)' in warning
                           for line,warning in zip((2127,2131,2140,2144),warnings)),warnings
        else:assert summaries[-1][1]=='0' and not warnings,warnings
        mapped_warning_summary[k]=dict(errors=0,warnings=int(summaries[-1][1]),messages=warnings)
        assert all(m in text for m in r['scenario_markers']) and r['scenario_markers']
    xml=ET.parse(OUT/'r17_software_final_20261101.xml').getroot()
    suite=xml if xml.tag=='testsuite' else xml.find('testsuite')
    assert int(suite.attrib['tests'])==174 and all(int(suite.attrib[k])==0 for k in ('errors','failures','skipped'))
    tk=load('r17_console_validation.json')['tests']
    assert len(tk)==106 and all(t['passed'] and not t['skipped'] for t in tk)
    for name,marker in [('r17_regress_run_modelsim_sin12_r16_nav_evidence_retry_20261101.log','SIN12_R16_NAV_EVIDENCE_ALL_PASS'),('r17_full_pipeline_20261101.log','SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS')]:
        text=(OUT/name).read_text();assert marker in text and '** Fatal' not in text,name
    stamp=datetime.fromtimestamp((pnr/'sin12_hdmi_system.fs').stat().st_mtime).strftime('%Y%m%d_%H%M%S')
    dest=OUT/('sin12_hdmi_r17_'+stamp);assert not dest.exists(),'Never overwrite archive'
    report=dict(candidate='SIN12 R17',usercode='534E3251',firmware='K11',map_id='2613',
      archive=str(dest),verified_at_local=datetime.now().isoformat(),hardware_access=False,pi_modified=False,
      hardware_source_count=len(hw),software_validation_source_count=len(sw),source_mismatches=[],
      netlist_sha256=nh,fs_sha256=sha(pnr/'sin12_hdmi_system.fs'),internal_sta_checks_pass=True,
      setup_violations=0,hold_violations=0,fmax_mhz=sta['fmax_mhz'],resources=sta['resources'],
      tables=sta['tables'],clocks=sta['clocks'],files=sta['files'],constraint_audit=audit,
      mapped=maps,mapped_warning_summary=mapped_warning_summary,software_tests=dict(nongui=174,isolated_tk=106,skips=0),
      ground_distance_calibrated=False,forward_counts_per_100mm=333,lateral_counts_per_100mm=1000,
      map_cell_mm=100,map_cells_per_axis=20,full_external_timing_signoff=False,vehicle_validated=False,
      margin_note=f"Minimum reported setup {sta['tables']['3.1.1 Setup Paths Table']['minimum_slack_ns']:+.3f}ns; internal STA evidence only, not complete external/vehicle signoff.",
      limitations=sta['limitations']+[
        '333 forward counts is provisional from approximate single measurement; real ground calibration required.',
        'Actual primitive cones at50MHz, not whole routed design SDF. Navigation ideal external plant/ticks accelerated.',
        'Search1000ms interval verified as external sample-strobe contract; settling900/1040ms uses real50MHz cycles.',
        'Mapped navigation coordinates expose only actual bits0..4,7; pruned bits5/6 not fabricated.',
        'Front-only ToF blind zones; no vehicle safety or17,4 ground coordinate calibration claim.',
        'R17 two-stage policy affects smart mission only; arrival+100mm sticky handoff,101 quiet samples,two fresh frames,60ms fine steps; original8degree and safety gates retained.',
        'Printed-digit robustness uses bounded roll/relative contrast,not new trained weights; real moving-field and Pi latency/deployment still require acceptance.'],
      preserved_history=[p.name for p in OUT.glob('sin12_hdmi_r17_*') if p.is_dir()],
      historical_baseline='Historical R12 Flash and15:02 R16 SRAM preserved. Separate18:26 R15 SRAM event reads0x534E324F; no R17 hardware programming or vehicle acceptance.',
      source_hashes={**hw,**sw})
    dest.mkdir();shutil.copytree(impl,dest/'impl')
    for rel in set(hw)|set(sw):
        target=dest/'sources'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,target)
        assert sha(target)==sha(ROOT/rel)
    for p in OUT.iterdir():
        if p.is_file() and 'r17' in p.name.lower():shutil.copy2(p,dest/p.name)
    # Final success must retain earlier failures and primitive-model warnings,
    # even when a later cached elaboration reports zero warnings.
    for history in OUT.glob('sin12_hdmi_r17_failed_*'):
        if not history.is_dir():continue
        for p in history.rglob('*'):
            if p.is_file() and (p.suffix.lower() in ('.log','.xml') or p.name=='FAILURE.json'):
                target=dest/'failure_logs'/history.name/p.relative_to(history)
                target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    for folder in ('sin12_r17_system_tof','sin12_r17_system_target','sin12_r17_mapped_recovery','sin12_r17_mapped_settle','sin12_r17_mapped_nav','sin12_r17_mapped_two_stage'):
        shutil.copytree(ROOT/'tmp'/folder,dest/'mapped_wrappers'/folder,ignore=shutil.ignore_patterns('sim','*.wlf','__pycache__'))
    serialized=json.dumps(report,ensure_ascii=False,indent=2)
    (dest/'BUILD_VERIFICATION.json').write_text(serialized,encoding='utf-8')
    (OUT/'SIN12_R17_BUILD_VERIFICATION_2026-11-01.json').write_text(serialized,encoding='utf-8')
    inventory={p.relative_to(dest).as_posix():sha(p) for p in dest.rglob('*') if p.is_file()}
    (dest/'ARCHIVE_SHA256.json').write_text(json.dumps(inventory,indent=2))
    assert all(sha(dest/p)==h for p,h in inventory.items())
    manifest(hw);manifest(sw);assert sha(net)==nh
    print(json.dumps(dict(archive=str(dest),files=len(inventory),hardware_access=False),indent=2))
if __name__=='__main__':main()
