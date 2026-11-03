"""Read-only preflight of the immutable, pinned R20 SRAM release."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / 'output/board/sin12_hdmi_r20_20261102_143316'
INVENTORY_SHA = '8329bdd53d98a5f07d574642b97595cc92864ac06537381546874e17009a2ad5'
FS_SHA = '509d6a799466a99a39f816745570e4341c450e6cb210454d8e92461abe111873'
VG_SHA = 'f61d0ad4a9f59d11c705bac70d41073684313c6a075cc454c869ef8c2d9fd09a'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    inventory_file = ARCHIVE / 'SHA256.json'
    assert sha(inventory_file) == INVENTORY_SHA, 'Pinned inventory drift'
    inventory = read(inventory_file)
    actual_files = {p.relative_to(ARCHIVE).as_posix() for p in ARCHIVE.rglob('*') if p.is_file()}
    assert len(inventory) == 420 and actual_files == set(inventory) | {'SHA256.json'}
    for name, digest in inventory.items():
        path = (ARCHIVE / name).resolve()
        assert path.is_relative_to(ARCHIVE.resolve()), name
        assert sha(path) == digest, name
    r = read(ARCHIVE / 'BUILD_VERIFICATION.json')
    assert r['passed'] and r['user_code'] == '534E3254' and r['revision'] == 'R20/K14/REV5_ENABLE16'
    assert r['hardware_sources'] == 58 and r['software_sources'] == 215
    assert r['counts_per_cell'] == 500 and r['early_stop_mm'] == 200
    assert r['hard_stop_mm'] == 100 and r['inflate_mm'] == 210
    for kind, count in [('build', 58), ('software', 215)]:
        manifest = read(ARCHIVE / f'evidence/sin12_hdmi_r20_{kind}_sources.json')
        assert len(manifest) == count
        for name, digest in manifest.items():
            assert sha(ARCHIVE / 'sources' / name) == digest, name
    sta = r['sta']
    assert sta['internal_sta_checks_pass'] and len(sta['checks']) == 16 and all(sta['checks'].values())
    assert sta['setup_violations'] == sta['hold_violations'] == 0
    for clock, freq in [('clk_50m', 50), ('camera_pclk', 75.002), ('camera_pixel', 75)]:
        assert sta['fmax_mhz'][clock] >= freq
    assert all(x['tns'] == 0 and x['endpoints'] == 0 for x in sta['tns']) and len(sta['tns']) == 12
    assert all(x['minimum_slack_ns'] > 0 for x in sta['tables'].values())
    for title in ('3.1.3.1 Recovery Paths Table[1]', '3.1.4.1 Removal Paths Table[1]'):
        assert sta['tables'][title]['reported_paths'] == 12 and len(sta['tables'][title]['endpoint_set']) == 4
    for title in ('3.1.3.2 Recovery Paths Table[2]', '3.1.4.2 Removal Paths Table[2]'):
        assert sta['tables'][title]['reported_paths'] == 200
    audit = r['constraint_audit']
    assert audit['passed'] and len(audit['active_constraints']) == 16
    assert len(audit['pixel_async_false_path_endpoints']) == 2
    config = audit['process_config']
    assert config['Optimization_Goal'] == 'Timing' and config['Max_Fanout'] == 1000
    assert config['Place_Option'] == '0' and config['Route_Option'] == '2'
    assert config['Run_Timing_Driven'] and config['Replicate_Resources']
    assert config['SSPI'] and not config['JTAG'] and not config['MSPI']
    opts = {x.get('type'): x.get('value') for x in ET.parse(ARCHIVE / 'impl/gwsynthesis/sin12_hdmi_system.prj').getroot().iter('Option')}
    assert opts['opt_goal'].lower() == 'timing' and int(opts['max_fanout']) == 1000
    command = (ARCHIVE / 'impl/pnr/cmd.do').read_text()
    assert '\n-place_option 0\n' in command and '\n-route_option 2\n' in command
    assert '\n-timing\n' in command and '\n-replicate\n' in command
    device = (ARCHIVE / 'impl/pnr/device.cfg').read_text()
    for setting in ('0x534E3254', 'set SSPI regular_io = true', 'set JTAG regular_io = false', 'set MSPI regular_io = false'):
        assert setting in device, setting
    for kind in ('TOF', 'TARGET', 'NAV'):
        m = r['mapped'][kind]
        assert m['passed'] and m['netlist_sha256'] == VG_SHA and m['internal_forces'] is False
    assert r['mapped']['TOF']['checks'] == 91 and r['mapped']['TARGET']['vectors'] == 2172
    nav = r['mapped']['NAV']
    assert nav['primitive_count'] == 26149 and nav['final_errors'] == 0 and nav['final_warnings'] == 4
    assert nav['scenario_markers'].count('R20_MAPPED_NAV_FRACTIONAL_ADAPTIVE_GOAL_PASS') == 4
    for marker in ('R20_MAPPED_NAV_854MM_REAL_DISTANCE_GRID12_ADAPTIVE_GOAL_PASS', 'R20_MAPPED_NAV_200MM_SUBTICK_STOP_300MM_CLEAR_ORIGINAL_GOAL_PASS', 'R20_MAPPED_NAV_TWO_NEW_OBSTACLES_ORIGINAL_GOAL_PASS', 'R20_MAPPED_NAV_SENSOR_LOSS_E02_NO_RESTART_PASS', 'R20_MAPPED_NAV_100MM_HARD_STOP_NO_RESTART_PASS'):
        assert marker in nav['scenario_markers'], marker
    assert r['rtl']['passed'] and len(r['rtl']['logs']) == 8 and r['host_tests'] == 21
    assert read(ARCHIVE / 'evidence/R20_TEST_VALIDATION.json')['passed']
    assert sha(ARCHIVE / 'impl/pnr/sin12_hdmi_system.fs') == r['fs_sha256'] == FS_SHA
    assert sha(ARCHIVE / 'impl/gwsynthesis/sin12_hdmi_system.vg') == r['netlist_sha256'] == VG_SHA
    print('Pinned R20 preflight PASS:420 files/58hardware/215software/STA16/constraints/3 mapped reports; no hardware access.')


if __name__ == '__main__':
    main()
