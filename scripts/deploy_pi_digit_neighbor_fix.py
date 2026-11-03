"""One-file guarded Pi deployment; no FPGA, task start or motion API calls."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path("/home/pi/ling_shu_vision")
STAGE = Path(__file__).resolve().parent
RELATIVE = "src/detection/printed_digit.py"
OLD_HASH = "9ff2a3d5d9f8e6c986087c904e8bc4020ee126b2be7821821fb881094e198f03"
REVISION = "printed-digit-v2-neighbor-filter-20261101"
SERVICE = "ling-shu-vision-gui.service"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def status():
    with urllib.request.urlopen("http://127.0.0.1:8080/api/status", timeout=4) as response:
        return json.load(response)


def safe(value):
    assert value.get("online") and value.get("task_mode") == "observe", "Require idle observe mode"
    assert not (value.get("mission_fpga") or {}).get("active"), "FPGA task active"
    assert not value.get("nav_goal_pending") and value.get("nav_goal_tx_enabled") is False
    assert value.get("motion_commands_enabled") is False
    assert value.get("mission_geometry_enabled") is False
    assert value.get("fpga_wheel_fault") in (0, "0")
    assert value.get("serial_connected") and value.get("mission_fpga_age_ms", 99999) < 2000


def compact(value):
    return {k:value.get(k) for k in ("online", "frame_id", "detector_revision", "fps", "detector_ms",
            "task_mode", "mission_fpga", "mission_fpga_age_ms", "serial_connected",
            "motion_commands_enabled", "mission_geometry_enabled", "nav_goal_pending", "nav_goal_tx_enabled",
            "fpga_tof_valid", "fpga_distance_mm", "fpga_wheel_fault", "detection_count", "detections")}


def service(action):
    subprocess.run(["sudo", "systemctl", action, SERVICE], check=True, timeout=25)


def atomic(path, data, mode):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, mode)
    os.replace(temporary, path)


def protected_hashes():
    files = set()
    for folder, pattern in (("src", "*.py"), ("config", "*"), ("web", "*"), ("assets", "*")):
        files.update(p for p in (ROOT / folder).rglob(pattern) if p.is_file())
    files.update(ROOT / p for p in ("run_pi_gui.sh", "run_pi.sh", "scripts/build_nav_map.py"))
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(files)
            if p.is_file() and p.relative_to(ROOT).as_posix() != RELATIVE}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-sha256", required=True)
    parser.add_argument("--event-id", required=True)
    parser.add_argument("--apply-safe-state-confirmed", action="store_true")
    args = parser.parse_args()
    assert args.event_id and all(c.isalnum() or c in "-_" for c in args.event_id)
    candidate = STAGE / RELATIVE
    target = ROOT / RELATIVE
    assert sha(candidate) == args.candidate_sha256
    assert sha(target) == OLD_HASH, "Unexpected production source; do not overwrite"
    native = json.loads((STAGE / "native_validation.json").read_text())
    assert native["passed"] and native["source_sha256"] == args.candidate_sha256
    assert native["native_test_count"] == 24 and len(native["real_saved_frames"]) == 6
    before = status()
    safe(before)
    report = dict(revision=REVISION, candidate_sha256=args.candidate_sha256, old_sha256=OLD_HASH,
                  before_status=compact(before), changed_files=[RELATIVE],
                  apply_requested=args.apply_safe_state_confirmed, passed=False,
                  fpga_reconfigured=False, flash_written=False, motion_api_called=False, task_started=False)
    if not args.apply_safe_state_confirmed:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return
    report_path = STAGE / "deployment_report.json"
    assert not report_path.exists(), "Existing event report; inspect before retry"
    backup = Path("/home/pi") / ("before-digit-neighbor-" + args.event_id)
    backup.mkdir(exist_ok=False)
    old = target.read_bytes()
    mode = stat.S_IMODE(target.stat().st_mode)
    saved = backup / RELATIVE
    saved.parent.mkdir(parents=True)
    shutil.copy2(target, saved)
    preserved = protected_hashes()
    report.update(backup=str(backup), preserved_sha256=preserved,
                  timestamp_utc=datetime.now(timezone.utc).isoformat(), safe_state_confirmed_by_user=True)
    (backup / "before_status.json").write_text(json.dumps(compact(before), ensure_ascii=False, indent=2))
    (backup / "rollback_manifest.json").write_text(json.dumps({RELATIVE:OLD_HASH}, indent=2))
    (backup / "service.unit").write_text(subprocess.check_output(["systemctl", "cat", SERVICE], text=True))
    try:
        service("stop")
        atomic(target, candidate.read_bytes(), mode)
        subprocess.run([str(ROOT / ".venv/bin/python"), "-m", "py_compile", str(target)], check=True, cwd=ROOT)
        service("start")
        frames = []
        last = None
        deadline = time.monotonic() + 55
        while time.monotonic() < deadline:
            time.sleep(1)
            try:
                current = status()
            except (OSError, ValueError):
                continue
            if current.get("detector_revision") != REVISION:
                continue
            safe(current)
            if current.get("frame_id") != last:
                frames.append(compact(current))
                last = current.get("frame_id")
            if len(frames) >= 5:
                break
        assert len(frames) >= 5, "No five fresh safe live frames"
        assert protected_hashes() == preserved, "Protected source/config changed"
        assert sha(target) == args.candidate_sha256
        report.update(passed=True, frames=frames,
                      live_target_detected=any(f.get("detection_count", 0) > 0 for f in frames),
                      service_state=subprocess.check_output(["systemctl", "show", SERVICE, "-p", "ActiveState", "-p", "MainPID"], text=True))
    except BaseException as error:
        report["error"] = str(error)
        service("stop")
        atomic(target, old, mode)
        service("start")
        report["rollback_restored"] = sha(target) == OLD_HASH
        raise
    finally:
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf8")
    print(json.dumps({"passed":True, "backup":str(backup), "report":str(report_path),
                      "live_target_detected":report["live_target_detected"], "last_status":frames[-1]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
