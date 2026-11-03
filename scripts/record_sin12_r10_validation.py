"""Summarize bounded offline tests; no serial/programmer calls."""
from pathlib import Path
import datetime,hashlib,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
expected={
 'r10_lateral_trim.log':'R10_LATERAL_LEFT_RIGHT_SIGN_WRAP_PAUSE_OWNER_LOW_SPEED_PASS',
 'r10_mission_align.log':'R10_CONTROLLED_ALIGNMENT_APPROACH_ARRIVAL_PASS',
 'r10_alignment_plant.log':'R10_DISTURBED_LATERAL_LOCK_ALIGN_APPROACH_ARRIVAL_PASS',
 'r10_full_uart.log':'SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS',
 'r10_telemetry.log':'R5_REAL_UART_PID_CRC_RANGE_BUSY_C_K06_O_ACK_ATOMIC_SNAPSHOT_PASS',
 'r10_original_trim.log':'R4_HEADING_FORWARD_REVERSE_WRAP_OWNER_SPIN_TRANSLATION_PASS',
 'r10_legacy_mission.log':'SIN11_MISSION_SEARCH_ARRIVAL_CANCEL_PASS',
 'r10_legacy_motor_mission.log':'SIN11_MISSION_MOTOR_PINS_ARBITRATION_PASS',
 'r10_map_nav.log':'R9_MAP2613_ORIGINAL_GOAL_CORNERS_INERTIAL_TURNS_PASS'}
rows=[]
for name,marker in expected.items():
 p=OUT/name;t=p.read_text(errors='replace')
 rows.append(dict(file=name,passed=marker in t and '** Fatal' not in t and 'Errors: 0, Warnings: 0' in t,
                  sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
tk=json.loads((OUT/'sin12_fixed_console_validation.json').read_text())
software=json.loads((OUT/'sin12_hdmi_r10_software_sources.json').read_text())
assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in software.items())
report=dict(candidate='SIN12 R10',time=datetime.datetime.now().isoformat(),hardware_access=False,
 rtl=rows,rtl_all_passed=all(r['passed'] for r in rows),nongui_tests=52,
 nongui_pass='52 passed' in (OUT/'r10_python_contracts.log').read_text(),
 tk_tests=len(tk['tests']),tk_passed=sum(t['passed'] for t in tk['tests']),tk_skipped=sum(t['skipped'] for t in tk['tests']),
 tk_all_passed=tk['all_passed'],software_sources=software,
 physical_vehicle_test_passed=False,full_routed_functional_signoff=False,internal_build_validation_complete=False)
(OUT/'SIN12_R10_OFFLINE_VALIDATION_2026-10-30.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:report[k] for k in ('rtl_all_passed','nongui_pass','tk_tests','tk_passed','tk_skipped','tk_all_passed')}))
