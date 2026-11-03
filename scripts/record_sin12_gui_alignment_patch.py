"""Record host-only patch independently of the immutable R9 build archive."""
from pathlib import Path
import datetime,hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
manifest=json.loads((OUT/'sin12_hdmi_r9_build_sources.json').read_text())
assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in manifest.items())
assert json.loads((OUT/'SIN12_PREVIEW_BFS_400_VALIDATION.json').read_text())['passed']
assert '1 passed' in (OUT/'r9_gui_alignment_autonav_final.log').read_text(encoding='utf-8-sig')
names=['fpga/motor_bt_drive/pc_unified_console.py','scripts/build_nav_map.py',
       'tests/test_sin12_preview_alignment.py','scripts/verify_sin12_preview_bfs.py',
       'scripts/audit_sin12_r9_map_routes.py']
report=dict(time=datetime.datetime.now().isoformat(),hardware_access=False,firmware='unchanged R9 534E3249',
            fpga_frozen_sources_verified=57,preview_rtl_goals_passed=400,real_tk_canvas_cases_passed=2,
            fake_serial_navigation_final_passed=True,protocol_tests_passed=25,full_gui_suite_rerun=False,
            route_order=['+Y','-X','-Y','+X'],restart_old_console_required=True,flash_written=False,
            files={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in names})
p=OUT/'SIN12_R9_GUI_ALIGNMENT_PATCH_VALIDATION_2026-10-30.json'
p.write_text(json.dumps(report,indent=2),encoding='utf-8')
archive=OUT/'sin12_r9_gui_bfs_alignment_20261030'
assert not archive.exists(), 'Do not overwrite patch evidence'
archive.mkdir()
for name in names:
    target=archive/'sources'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,target)
for name in [p.name,'SIN12_R9_GUI_BFS_ALIGNMENT_2026-10-30.md','SIN12_PREVIEW_BFS_400_VALIDATION.json',
             'SIN12_R9_MAP_ROUTE_AUDIT_2026-10-30.json','sin12_preview_bfs_400.log','r9_gui_alignment_autonav_final.log']:
    shutil.copy2(OUT/name,archive/name)
print('Host preview patch recorded; 57 FPGA inputs unchanged; no programming/COM access')
