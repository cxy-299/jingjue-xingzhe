import hashlib
import json
from pathlib import Path
import re
import zipfile

root=Path(__file__).resolve().parents[1]
board=root/'output/board'
bitstream=board/'SIN11_R2_RANGE_STOP_2026-10-27.fs'
timing=(board/'sin11_r2_timing.tr').read_text(errors='replace')
setup=int(re.search(r'<Numbers of Setup Violated Endpoints>:(\d+)',timing)[1])
hold=int(re.search(r'<Numbers of Hold Violated Endpoints>:(\d+)',timing)[1])
fmax=float(re.search(r'50\.000\(MHz\)\s+([\d.]+)\(MHz\)',timing)[1])
assert setup==hold==0 and fmax>=50
assert '0x534E3143' in (board/'sin11_r2_read_code.log').read_text()
assert 'Finished.' in (board/'sin11_r2_sram_download.log').read_text()
assert '63 passed' in (board/'sin11_r2_core_tests.log').read_text()
for name in ('capable','reject','snapshot'):
    assert '1 passed' in (board/f'sin11_r2_gui_{name}.log').read_text()
for name,marker in [('range_priority','SIN11_MISSION_SEARCH_ARRIVAL_CANCEL_PASS'),
                    ('motor_range','SIN11_MISSION_MOTOR_PINS_ARBITRATION_PASS')]:
    text=(board/f'sin11_r2_{name}.log').read_text(errors='replace')
    assert marker in text and '** Fatal' not in text
paths=[
 'fpga/motor_bt_drive/vision_mission_guard.v','fpga/motor_bt_drive/build_sin11_r2.tcl',
 'fpga/motor_bt_drive/pc_async_transport.py','fpga/motor_bt_drive/pc_unified_console.py',
 'fpga/motor_bt_drive/pc_unified_model.py','fpga/motor_bt_drive/acg720_motor_bt_drive.v',
 'fpga/motor_bt_drive/bt_combined_diag_uart.v','fpga/motor_four_closed_loop/acg720_motor_four_closed_loop.v',
 'fpga/motor_bt_drive/tb_sin11_mission.sv','fpga/motor_bt_drive/tb_sin11_motor_integration.sv',
 'tests/test_async_transport.py','tests/test_mission_console.py',
 'output/board/SIN11_R2_RANGE_STOP_MAINTENANCE_2026-10-27.md','scripts/archive_sin11_r2.py']
hashes={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
archive=board/'sin11_r2_changed_sources_2026-10-27.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as bundle:
    for p in paths:bundle.write(root/p,p)
    bundle.writestr('manifest.sha256.json',json.dumps(hashes,indent=2))
result=dict(revision='SIN11-R2',user_code='0x534E3143',bitstream=bitstream.name,
    sha256=hashlib.sha256(bitstream.read_bytes()).hexdigest(),fmax_mhz=fmax,
    setup_violations=setup,hold_violations=hold,logic_used=12411,registers_used=4944,dsp_used=7,
    tests=dict(core=63,isolated_gui=3,rtl_range_unit='PASS',rtl_motor_outputs='PASS'),
    download='SRAM Program Finished and independent Read User Code match; 5.29s',
    download_status='0x72026020',flash='unchanged',pi_package='no update required',
    hardware_static='COM9 actual I1/T1/H0/F00/W0, M1-M4 A0/D0/F0, J0/Q0/S00; OS TX completion logged; permissions off',
    hardware_motion='pending; agent did not start motors',
    incident_excerpt_sha256=hashlib.sha256((board/'sin11_r2_incident_excerpt.log').read_bytes()).hexdigest(),
    timeout_root_cause='2.82s GUI logging/lease gap proved; exact blocking OS call unknown on old build',
    source_sha256=hashes,changed_source_archive=archive.name,
    archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest())
(board/'SIN11_R2_VALIDATION_2026-10-27.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ('revision','user_code','sha256','fmax_mhz','download')},indent=2))
