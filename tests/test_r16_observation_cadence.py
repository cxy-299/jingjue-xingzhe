from pathlib import Path
from src.comm.pid_tuning import mission_lease_ms, parse_pid_status

ROOT = Path(__file__).resolve().parents[1]

def test_r16_telemetry_and_lease():
    assert parse_pid_status("K10000000040100")["version"] == 16
    assert mission_lease_ms(16) == 600
    assert mission_lease_ms(15) == 600
    assert mission_lease_ms(18) == 300

def test_r16_only_changes_sway_and_preserves_forward_rest():
    text = (ROOT / "fpga/motor_bt_drive/acg720_motor_bt_drive.v").read_text(encoding="utf-8")
    assert ".RECOVERY_RUN_MS(100)" in text
    assert ".RECOVERY_REST_MS(REV5_ENABLE>=12?1000:300)" in text
    assert ".ALIGN_REST_MS(REV5_ENABLE>=12?1000:300)" in text
    assert ".APPROACH_REST_MS(300)" in text
    assert ".OBSERVE_SETTLE_MS(REV5_ENABLE>=12?1000:0)" in text
