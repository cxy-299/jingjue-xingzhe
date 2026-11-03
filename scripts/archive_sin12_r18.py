"""Strict, independent R18 evidence snapshot; --failure preserves before repair."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--failure');args=parser.parse_args()
    hardware=json.loads((OUT/'sin12_hdmi_r18_build_sources.json').read_text())
    software=json.loads((OUT/'sin12_hdmi_r18_software_sources.json').read_text())
    assert len(hardware)==58
    assert all(sha(ROOT/n)==d for n,d in hardware.items()),'Frozen hardware changed'
    assert all(sha(ROOT/n)==d for n,d in software.items()),'Refresh verification manifest before snapshot'
    verification=dict(passed=False,hardware_sources=len(hardware),software_sources=len(software),
       user_code='534E3252',revision='R18/K12/REV5_ENABLE14',counts_per_cell=500,
       scale_basis='User R12 measurement:1000counts/200mm; no new ground calibration',
       mission_source_unchanged=json.loads((OUT/'R18_UNCHANGED_MISSION_BASELINE.json').read_text()),
       hardware_access=False,fpga_programmed=False,flash_written=False,vehicle_tested=False,
       failure=args.failure,limitations=[
         'Single forward ToF does not cover a22cm-wide swept volume;10cm sidestep does not guarantee clearance',
         'Fixed detour cannot override occupied cells/boundaries/denied edges; reason14 stops',
         '500counts/100mm derived from user measurement; current real stopping/coast not validated',
         'Mapped external plant/ticks are scaled; functional cone is not whole-system SDF',
         'No mapped speed port before actual producer verification; RTL/fullUART speed4 coverage only',
         'External IO lacks delay budgets; MPW coverage/PR1014 PCLK/HDMI sensor captions remain unsigned'])
    if not args.failure:
        assert (OUT/'sin12_hdmi_r18_build_exit.txt').read_text().strip()=='0'
        sta=json.loads((OUT/'SIN12_R18_TIMING_INSPECTION_2026-11-01.json').read_text())
        audit=json.loads((OUT/'SIN12_R18_CONSTRAINT_AUDIT.json').read_text())
        assert sta['internal_sta_checks_pass'] and all(sta['checks'].values()) and audit['passed']
        net=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg';digest=sha(net)
        mapped={}
        for kind in ('TOF','TARGET','NAV'):
            path=OUT/f'SIN12_R18_MAPPED_{kind}_VALIDATION.json'
            report=json.loads(path.read_text())
            assert report.get('passed'),path
            assert report.get('netlist_sha256',report.get('full_system_netlist_sha256'))==digest,path
            mapped[kind]=report
        nav=mapped['NAV'];wrapper=ROOT/'tmp/sin12_r18_mapped_nav/mapped.v'
        assert nav['mapped_wrapper_sha256']==sha(wrapper)
        assert nav['testbench_sha256']==sha(ROOT/'fpga/motor_bt_drive/tb_sin12_r18_mapped_nav.sv')
        markers=nav['scenario_markers']
        assert any('500' in m for m in markers) and any('LEFT_DETOUR_ORIGINAL_GOAL' in m for m in markers)
        assert 'R18_MAPPED_NAV_LEFT_FORWARD_RIGHT_RESTORE_ORIGINAL_GOAL_PASS' in markers
        assert mapped['TOF']['checks']==91 and mapped['TARGET']['vectors']==2172
        gui=json.loads((OUT/'r18_console_validation.json').read_text())
        assert gui['all_passed'] and len(gui['tests'])==32
        xml=ET.parse(OUT/'r18_contract_regression.xml').getroot().findall('testsuite')
        assert sum(int(s.attrib['tests']) for s in xml)==51
        assert all(int(s.attrib[k])==0 for s in xml for k in ('failures','errors','skipped'))
        required={
          'r18_second_left_detour_coast.log':'R18_FIXED_LEFT_NAV_ALL_PASS',
          'r18_second_full_uart.log':'SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS',
          'r18_real_uart_k12.log':'R18_REAL_UART_J_ACTIVE_S11_ORIGINAL_ID_AND_K12_PASS',
          'r18_regression_r17_full.log':'SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS',
          'r18_second_regression_two_stage.log':'SIN12_R17_TWO_STAGE_ALL_PASS',
          'r18_regression_r16_nav.log':'SIN12_R16_NAV_EVIDENCE_ALL_PASS',
          'r18_regression_r12_nav.log':'R9_MAP2613_ORIGINAL_GOAL_CORNERS_INERTIAL_TURNS_PASS'}
        for name,marker in required.items():
            text=(OUT/name).read_text()
            assert marker in text and '** Fatal' not in text and '** Error' not in text,name
            assert re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)',text)[-1]==('0','0'),name
        assert all(x['unchanged'] for x in verification['mission_source_unchanged'].values())
        verification.update(passed=True,netlist_sha256=digest,fs_sha256=sha(ROOT/'fpga/sin12_hdmi/impl/pnr/sin12_hdmi_system.fs'),
                            sta=sta,constraint_audit=audit,mapped=mapped,gui_tests=32,contract_tests=51)
    stamp=datetime.now().strftime('%Y%m%d_%H%M%S')
    if args.failure:assert all(c.isalnum() or c in '-_' for c in args.failure)
    dest=OUT/(('sin12_hdmi_r18_failed_'+args.failure+'_') if args.failure else 'sin12_hdmi_r18_')
    dest=Path(str(dest)+stamp);dest.mkdir(exist_ok=False)
    shutil.copytree(ROOT/'fpga/sin12_hdmi/impl',dest/'impl')
    for name in set(hardware)|set(software):
        target=dest/'sources'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,target)
    for path in OUT.iterdir():
        if path.is_file() and ('r18' in path.name.lower() or path.name=='R18_UNCHANGED_MISSION_BASELINE.json'):
            target=dest/'evidence'/path.name;target.parent.mkdir(exist_ok=True);shutil.copy2(path,target)
        elif path.is_dir() and path.name.startswith('r18_'):
            shutil.copytree(path,dest/'history'/path.name)
    prepared=ROOT/'tmp/sin12_r18_mapped_nav'
    if prepared.exists():
        for name in ('mapped.v','extraction.json','run.do'):
            if (prepared/name).exists():
                target=dest/'mapped_nav'/name;target.parent.mkdir(exist_ok=True);shutil.copy2(prepared/name,target)
    (dest/'BUILD_VERIFICATION.json').write_text(json.dumps(verification,indent=2),encoding='utf8')
    hashes={p.relative_to(dest).as_posix():sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'SHA256.json').write_text(json.dumps(hashes,indent=2),encoding='utf8')
    check=json.loads((dest/'SHA256.json').read_text());assert all(sha(dest/n)==d for n,d in check.items())
    print(json.dumps(dict(archive=str(dest),files=len(check),passed=verification['passed']),ensure_ascii=False))


if __name__=='__main__':main()
