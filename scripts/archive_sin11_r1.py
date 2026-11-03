"""Archive the checked SIN11-R1 build and its exact changed sources."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

root = Path(__file__).resolve().parents[1]
board = root / 'output/board'
bitstream = board / 'SIN11_R1_PI_EVIDENCE_2026-10-27.fs'
timing = (board / 'sin11_r1_timing.tr').read_text(encoding='utf-8', errors='replace')
setup = int(re.search(r'<Numbers of Setup Violated Endpoints>:(\d+)', timing)[1])
hold = int(re.search(r'<Numbers of Hold Violated Endpoints>:(\d+)', timing)[1])
fmax = float(re.search(r'50\.000\(MHz\)\s+([\d.]+)\(MHz\)', timing)[1])
assert setup == hold == 0 and fmax >= 50
assert '0x534E3142' in (board/'sin11_r1_read_code.log').read_text()
assert 'Finished.' in (board/'sin11_r1_sram_download.log').read_text()
markers = {
    'pi_evidence':'PI_ZERO_REFERENCE_LONG_COUNTER_FIRST_FAULT_EVIDENCE_PASS',
    'telemetry':'SIN11_FIVE_FRAME_UART_PASS',
    'integration':'SIN11_MISSION_MOTOR_PINS_ARBITRATION_PASS',
    'mission':'SIN11_MISSION_SEARCH_ARRIVAL_CANCEL_PASS',
    'packets':'SIN11_CRC_MISSION_ID_ASCII_ISOLATION_PASS',
    'sin10':'SIN10_MOTOR_PIN_ARBITRATION_UART_PASS',
    'four_pi':'PASS tb_acg720_motor_four_closed_loop',
    'stagger':'PASS tb_start_stagger_125',
    'nav':'PASS tb_acg720_motor_bt_nav',
}
for name, marker in markers.items():
    report = (board/f'sin11_r1_{name}.log').read_text(errors='replace')
    assert marker in report and '** Fatal' not in report, name
assert '58 passed' in (board/'sin11_r1_core_tests.log').read_text()
assert '2 passed' in (board/'sin11_r1_gui_tests.log').read_text()
assert '1 passed' in (board/'sin11_r1_gui_evidence_test.log').read_text()
paths = [
    'fpga/motor_four_closed_loop/acg720_motor_four_closed_loop.v',
    'fpga/motor_bt_drive/acg720_motor_bt_drive.v',
    'fpga/motor_bt_drive/bt_combined_diag_uart.v',
    'fpga/motor_bt_drive/pc_unified_console.py',
    'fpga/motor_bt_drive/pc_unified_model.py',
    'fpga/motor_bt_drive/build_sin11_r1.tcl',
    'fpga/motor_bt_drive/tb_pi_fault_evidence.sv',
    'fpga/motor_bt_drive/run_modelsim_pi_evidence.do',
    'fpga/motor_bt_drive/tb_sin11_telemetry.sv',
    'fpga/motor_bt_drive/run_modelsim_stagger.do',
    'fpga/motor_bt_drive/run_modelsim_nav.do',
    'tests/test_motor_fault_evidence.py',
    'tests/test_mission_console.py',
    'output/board/SIN11_R1_M3_LOGIC_REVIEW_2026-10-27.md',
    'scripts/archive_sin11_r1.py',
]
hashes = {name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in paths}
archive = board/'sin11_r1_changed_sources_2026-10-27.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
    for name in paths:
        bundle.write(root/name, name)
    bundle.writestr('manifest.sha256.json', json.dumps(hashes, indent=2))
record = dict(
    revision='SIN11-R1', user_code='0x534E3142', bitstream=bitstream.name,
    sha256=hashlib.sha256(bitstream.read_bytes()).hexdigest(),
    fmax_mhz=fmax, setup_violations=setup, hold_violations=hold,
    logic_used=12429, registers_used=4944, dsp_used=7,
    simulations=markers, python_core_passed=58,
    gui_mission_workflow_passed=2, gui_fault_evidence_standalone_passed=1,
    test_environment_note='Combined Tk runs had one init.tcl environment skip and a Tk teardown warning; isolated new GUI evidence case passed. Original logs retained.',
    source_sha256=hashes, changed_source_archive=archive.name,
    archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
    download='SRAM Program Finished, 5.4s; independent read matches',
    download_status='0x72026020', flash='unchanged', pi_update='not required',
    hardware_static='New GUI COM9 connected; real M1-M4 A0/D0/F0, I1/T1/H0/F00/W0, J0/Q00000000/S00, authorization off; TX/RX disk log verified',
    incident='Original SIN11 M3 W4 protection observed; user reported subsequent retry normal. Original root cause not established.',
    hardware_motion='R1 motion retest pending; no autonomous motor command sent by agent',
)
(board/'SIN11_R1_VALIDATION_2026-10-27.json').write_text(json.dumps(record, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
print(json.dumps({k:record[k] for k in ('revision','user_code','sha256','fmax_mhz','download')}, indent=2))
