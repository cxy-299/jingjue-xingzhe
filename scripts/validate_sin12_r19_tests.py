"""Validate actual completed R19 logs/XML, not process startup or exit alone."""
from pathlib import Path
import json,hashlib,re,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    paths=[]
    def xml(path,expected):
        suites=ET.parse(path).getroot().findall('testsuite')
        assert sum(int(s.attrib['tests']) for s in suites)==expected,path
        assert all(int(s.attrib[k])==0 for s in suites for k in ('errors','failures','skipped')),path
        paths.append(path)
    xml(OUT/'r19_contract_regression.xml',64)
    gui=json.loads((OUT/'r19_console_validation.json').read_text())
    assert gui['all_passed'] and len(gui['tests'])==41
    assert all(r['exit_code']==0 and r['passed'] for r in gui['tests'])
    paths.append(OUT/'r19_console_validation.json')
    for i in range(41):xml(OUT/f'r19_gui_{i:02d}.xml',1)
    xml(OUT/'r19_task5_disconnect.xml',1)
    xml(OUT/'r19_task5_vision_silent.xml',1)
    logs={
      'r19_sixth_left_detour.log':'R19_FIXED_LEFT_NAV_ALL_PASS',
      'r19_ninth_full_uart.log':'SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS',
      'r19_final_uart_k13.log':'R19_REAL_UART_J_ACTIVE_S11_ORIGINAL_ID_AND_K13_PASS',
      'r19_sixth_regression_r18_left.log':'R18_FIXED_LEFT_NAV_ALL_PASS',
      'r19_ninth_two_stage.log':'SIN12_R17_TWO_STAGE_ALL_PASS'}
    for name,marker in logs.items():
        path=OUT/name;text=path.read_text();assert marker in text and '** Fatal' not in text and '** Error' not in text,path
        assert re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)',text)[-1]==('0','0'),path
        paths.append(path)
    rtl=(OUT/'r19_sixth_left_detour.log').read_text()
    markers=re.findall(r'^# (R19_\S+_PASS)$',rtl,re.M)
    assert len(markers)==22,markers #21 scenarios + final marker
    baseline=json.loads((OUT/'R19_UNCHANGED_MISSION_BASELINE.json').read_text())
    approval_path=OUT/'R19_PROTECTED_SOURCE_CHANGE_REQUEST.json'
    approval=json.loads(approval_path.read_text())
    assert approval['status']=='applied_authorized_equivalent_changes' and approval['production_applied']
    assert approval['explicit_user_answer']=='允许这两处等价修改（推荐）'
    approved={r['source']:r for r in approval['requests']}
    assert set(approved)=={'fpga/motor_bt_drive/vision_mission_guard.v','fpga/motor_bt_drive/chassis_trim.v'}
    for name,value in baseline.items():
        assert sha(ROOT/name)==value['current_sha256']
        if value['unchanged']:assert value['current_sha256']==value['sealed_r18_sha256']
        else:
            r=approved[name]
            assert value['authorized_equivalent_change'] and value['current_sha256']==r['candidate_sha256']
            assert value['sealed_r18_sha256']==r['production_sha256']
    widths_path=OUT/'R19_AUTHORIZED_WIDTH_RTL_VALIDATION.json'
    widths=json.loads(widths_path.read_text());assert widths['passed'] and len(widths['results'])==7
    assert widths['approval_sha256']==sha(approval_path)
    assert all(sha(ROOT/n)==v for n,v in widths['files'].items())
    assert widths['approved_source_hashes']=={n:r['candidate_sha256'] for n,r in approved.items()}
    paths.extend([approval_path,widths_path])
    paths.extend(ROOT/n for n in widths['files'])
    paths.append(OUT/'R19_UNCHANGED_MISSION_BASELINE.json')
    owner_dir=OUT/'r19_owner_mux_review'
    owner=json.loads((owner_dir/'PROOF.json').read_text())
    assert owner['passed'] and owner['exhaustive_owner_control_data_bit_cases']==4096
    assert owner['randomized_full_bus_cases']==16384
    assert sha(ROOT/'fpga/motor_bt_drive/acg720_motor_bt_drive.v')==owner['candidate_sha256']
    for name in ('PROOF.json','truth.log','full_uart.log','candidate.diff','acg720_motor_bt_drive_candidate.v'):
        paths.append(owner_dir/name)
    result=dict(passed=True,unit_tests=64,isolated_gui_tests=41,task5_additional_gui_regressions=2,new_rtl_scenarios=21,
        real_hardware_access=False,vehicle_tested=False,rtl_scaled_plant=True,
        integration_sensor_forces=True,not_mapped_or_whole_system_sdf=True,
        owner_mux_two_state_cases=4096,owner_mux_bus_vectors=16384,
        owner_mux_production_sha256=owner['candidate_sha256'],
        authorized_equivalent_source_changes=approved,production_width_regression_groups=7,
        rtl_markers=markers,files={p.relative_to(ROOT).as_posix():sha(p) for p in paths})
    (OUT/'R19_TEST_VALIDATION.json').write_text(json.dumps(result,indent=2))
    print('R19 tests PASS:64 unit/41 isolated fake-port GUI/21 RTL + UART and regressions')
if __name__=='__main__':main()
