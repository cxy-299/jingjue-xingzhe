"""Independent R19 snapshot; failures retain all evidence before repair."""
import argparse,hashlib,json,shutil,re
from pathlib import Path
from datetime import datetime
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('--failure');a=p.parse_args()
    hardware=json.loads((OUT/'sin12_hdmi_r19_build_sources.json').read_text())
    software=json.loads((OUT/'sin12_hdmi_r19_software_sources.json').read_text())
    assert len(hardware)==58 and all(sha(ROOT/n)==v for n,v in hardware.items())
    assert all(sha(ROOT/n)==v for n,v in software.items()),'Refresh software manifest'
    evidence=dict(passed=False,failure=a.failure,hardware_sources=len(hardware),software_sources=len(software),
        user_code='534E3253',revision='R19/K13/REV5_ENABLE15',counts_per_cell=500,
        detour='left1 / forward3 individually probed cells / right1 / restore heading and original goal',
        programmed=False,flash_written=False,vehicle_tested=False,
        limitations=['Nominal500counts/100mm derived from user R12 measurement, not fresh ground calibration',
          '10cm sidestep cannot guarantee clearance for22cm body; occupied/bounds/denied edges still stop',
          'Single front ToF blind spots; no whole-system SDF or physical swept-volume signoff',
          'Mapped external plant/ticks scaled; speed4 only RTL/full UART unless real mapped producer observed',
          'External IO delays/MPW/PR1014 ordinaryPCLK/HDMI captions remain unsigned',
          'Failure snapshots may contain older implementation products; never treated as R19 STA PASS'])
    if not a.failure:
        sta=json.loads((OUT/'SIN12_R19_TIMING_INSPECTION_2026-11-01.json').read_text())
        audit=json.loads((OUT/'SIN12_R19_CONSTRAINT_AUDIT.json').read_text())
        assert sta['internal_sta_checks_pass'] and all(sta['checks'].values()) and audit['passed']
        assert (OUT/'sin12_hdmi_r19_build_exit.txt').read_text().strip()=='0'
        assert all(sha(ROOT/'fpga/sin12_hdmi/impl/pnr'/n)==v['sha256'] for n,v in sta['files'].items()),'STA files changed'
        assert all(sha(ROOT/'fpga/sin12_hdmi'/n)==v for n,v in audit['source_hashes'].items()),'Constraint audit files changed'
        net=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg';digest=sha(net)
        reports={k:json.loads((OUT/f'SIN12_R19_MAPPED_{k}_VALIDATION.json').read_text()) for k in ('TOF','TARGET','NAV')}
        for r in reports.values():assert r['passed'] and r.get('netlist_sha256',r.get('full_system_netlist_sha256'))==digest
        assert reports['TOF']['checks']==91 and reports['TARGET']['vectors']==2172
        for kind,folder,bench in [('TOF','sin12_r19_system_tof','fpga/sensors/tb_tof_ascii_fault_recovery.sv'),
                                  ('TARGET','sin12_r19_system_target','fpga/motor_bt_drive/tb_sin12_r7_target.sv')]:
            r=reports[kind];prepared=ROOT/'tmp'/folder
            assert r['mapped_wrapper_sha256']==sha(prepared/'wrapper.v')
            assert r['mapped_source_sha256']==sha(prepared/'mapped.v')
            assert r['testbench_sha256']==sha(ROOT/bench)
        nav=reports['NAV']
        assert nav['mapped_wrapper_sha256']==sha(ROOT/'tmp/sin12_r19_mapped_nav/mapped.v')
        assert nav['testbench_sha256']==sha(ROOT/'fpga/motor_bt_drive/tb_sin12_r19_mapped_nav.sv')
        assert 'R19_MAPPED_NAV_LEFT_FORWARD_THREE_RIGHT_RESTORE_ORIGINAL_GOAL_PASS' in nav['scenario_markers']
        assert 'R19_MAPPED_NAV_WEST_NEGATIVE_CONSTANTS_FIVE_LEGS_ORIGINAL_GOAL_PASS' in nav['scenario_markers']
        assert 'R19_MAPPED_NAV_SOUTH_NEGATIVE_CONSTANTS_FIVE_LEGS_ORIGINAL_GOAL_PASS' in nav['scenario_markers']
        tests=json.loads((OUT/'R19_TEST_VALIDATION.json').read_text());assert tests['passed']
        assert all(sha(ROOT/n)==v for n,v in tests['files'].items()),'Test evidence changed'
        boundary=json.loads((OUT/'R19_MAPPED_BOUNDARY_INSPECTION.json').read_text())
        assert boundary['netlist_sha256']==digest and boundary['active_high_clear']
        assert nav['original_interface_cut_points']['reset']==boundary['reset_signal']
        assert nav['coordinate_observation_bits']==next(iter(boundary['coordinate_observed_bits'].values()))
        evidence.update(passed=True,sta=sta,constraint_audit=audit,mapped=reports,tests=tests,
            mapped_boundary=boundary,netlist_sha256=digest,fs_sha256=sha(ROOT/'fpga/sin12_hdmi/impl/pnr/sin12_hdmi_system.fs'))
    suffix=('failed_'+a.failure+'_') if a.failure else ''
    assert not a.failure or all(c.isalnum() or c in '-_' for c in a.failure)
    dest=OUT/('sin12_hdmi_r19_'+suffix+datetime.now().strftime('%Y%m%d_%H%M%S'));dest.mkdir()
    shutil.copytree(ROOT/'fpga/sin12_hdmi/impl',dest/'impl')
    for n in set(hardware)|set(software):
        target=dest/'sources'/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,target)
    for path in OUT.iterdir():
        if path.is_file() and 'r19' in path.name.lower():
            target=dest/'evidence'/path.name;target.parent.mkdir(exist_ok=True);shutil.copy2(path,target)
        elif path.is_dir() and path.name.startswith('r19_'):shutil.copytree(path,dest/'history'/path.name)
    for kind,folder in [('nav','sin12_r19_mapped_nav'),('tof','sin12_r19_system_tof'),('target','sin12_r19_system_target')]:
        prepared=ROOT/'tmp'/folder
        if prepared.exists():
            for name in ('mapped.v','wrapper.v','extraction.json','run.do'):
                if (prepared/name).exists():
                    target=dest/('mapped_'+kind)/name;target.parent.mkdir(exist_ok=True);shutil.copy2(prepared/name,target)
    (dest/'BUILD_VERIFICATION.json').write_text(json.dumps(evidence,indent=2))
    hashes={p.relative_to(dest).as_posix():sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'SHA256.json').write_text(json.dumps(hashes,indent=2))
    assert all(sha(dest/n)==v for n,v in json.loads((dest/'SHA256.json').read_text()).items())
    print(json.dumps(dict(archive=str(dest),files=len(hashes),passed=evidence['passed'])))
if __name__=='__main__':main()
