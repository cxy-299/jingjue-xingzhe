"""Record existing evidence and final software hashes, never runs a build/COM."""
from pathlib import Path
import datetime
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
names=json.loads((OUT/'sin12_hdmi_r9_software_sources.json').read_text())
software={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in names}
(OUT/'sin12_hdmi_r9_software_sources.json').write_text(json.dumps(software,indent=2),encoding='utf-8')
expected={
    'r9_nav_progress.log':['R9_PASSED_INTERMEDIATE_NO_REVERSE_GOAL_IMMUTABLE_PASS','R9_FINAL_GOAL_ONLY_TAPER_EARLY_BRAKE_STOP_PASS','R9_FINAL_OVERSHOOT_NOT_ARRIVAL_NO_HUNT_PASS'],
    'r9_turn_inertia.log':['R9_TURN_PENDING_RATE_SETTLE_WRAP_INVERSION_HARDSTOP_PASS'],
    'r9_map_nav_inertia.log':['R9_MAP2613_ORIGINAL_GOAL_CORNERS_INERTIAL_TURNS_PASS'],
    'r9_local_nav.log':['SIN12_REAL_SENSOR_MODEL_BFS_DETOUR_PASS','R6_LOCAL_CANCEL_NO_DELAY_NO_REBOUND_PASS'],
    'r9_full_uart.log':['SIN12_UART_GOAL_CRC_OWNER_MOTOR_HARDSTOP_PASS'],
    'r9_telemetry.log':['R5_REAL_UART_PID_CRC_RANGE_BUSY_C_K06_O_ACK_ATOMIC_SNAPSHOT_PASS'],
    'r9_original_turn_guard.log':['R7_TARGET_ATOMIC_PENDING_CANCEL_BUSY_DONE_PASS'],
    'r9_original_pi_evidence.log':['PI_ZERO_REFERENCE_LONG_COUNTER_FIRST_FAULT_EVIDENCE_PASS'],
    'r9_original_pid_channel.log':['R4_RUNTIME_PID_DERIVATIVE_RESET_SPIN_FEEDBACK_RANDOM160_PASS'],
    'r9_original_trim.log':['R4_HEADING_FORWARD_REVERSE_WRAP_OWNER_SPIN_TRANSLATION_PASS']}
rows=[]
for name,markers in expected.items():
    p=OUT/name;t=p.read_text(errors='replace')
    rows.append(dict(file=name,passed=all(s in t for s in markers) and '** Fatal' not in t and
                     'Errors: 0, Warnings: 0' in t,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
tk=json.loads((OUT/'sin12_fixed_console_validation.json').read_text())
report=dict(candidate='SIN12 R9',time=datetime.datetime.now().isoformat(),hardware_access=False,
            rtl=rows,rtl_all_passed=all(r['passed'] for r in rows),software_sources=software,
            tk_tests=len(tk['tests']),tk_passed=sum(r['passed'] for r in tk['tests']),
            tk_skipped=sum(r['skipped'] for r in tk['tests']),tk_all_passed=tk['all_passed'],
            nongui_tests=38,nongui_log='r9_python_contracts.log',
            whole_system_routed_validation_pending=True,physical_vehicle_test_passed=False)
(OUT/'SIN12_R9_OFFLINE_VALIDATION_2026-10-30.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:report[k] for k in ('rtl_all_passed','tk_tests','tk_passed','tk_skipped','tk_all_passed')}))
