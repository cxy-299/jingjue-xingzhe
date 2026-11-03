"""Deploy only the reviewed R14 printed-digit vision files to the Raspberry Pi.

This script runs on the Pi. It requires an explicit operator safe-state
confirmation, preserves motion/navigation configuration and backs up every
changed production file before restarting the vision service.
"""
import argparse
import copy
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

import yaml

ROOT = Path('/home/pi/ling_shu_vision')
STAGE = Path('/home/pi/ling_shu_digit_r14_latest_20261031')
CANDIDATE = STAGE / 'candidate'
ARCHIVE = STAGE / 'pi_source_candidate.zip'
EXPECTED_ARCHIVE_SHA256 = 'b4a34f41168ab9eb0b1982054fb52439246ba26d37f044b3a118955acd58b6b6'
EXPECTED_REVISION = 'printed-digit-v1-reacquire-20261031'
SERVICE = 'ling-shu-vision-gui.service'
REPORT = STAGE / 'deployment-report.json'
DEPLOY_FILES = (
    'src/detection/printed_digit.py',
    'src/detection/factory.py',
    'src/detection/locked_target.py',
    'src/detection/mission_geometry.py',
    'src/detection/semantic_mission.py',
    'src/core/a4_targets.py',
    'src/web_gui.py',
    'web/dashboard.html',
    'web/a4-targets.html',
    'assets/a4_digits_templates.json',
)
PRESERVE_FILES = (
    'config/nav-map-2m.json',
    'scripts/build_nav_map.py',
    'src/core/follow_control.py',
    'src/comm/autonav.py',
    'src/comm/pid_tuning.py',
    'run_pi_gui.sh',
)


def sha(data):
    if isinstance(data, Path):
        data = data.read_bytes()
    return hashlib.sha256(data).hexdigest()


def status():
    with urllib.request.urlopen('http://127.0.0.1:8080/api/status', timeout=4) as response:
        return json.load(response)


def service(action):
    subprocess.run(['sudo', 'systemctl', action, SERVICE], check=True, timeout=25)


def atomic(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, mode)
    os.replace(temporary, path)


def compact(value):
    keys = (
        'online', 'frame_id', 'model', 'detector_backend', 'detector_revision',
        'detector_ms', 'fps', 'resolution', 'task_mode', 'task_state',
        'mission_fpga', 'mission_fpga_age_ms', 'serial_connected',
        'serial_frames_sent', 'serial_last_error', 'motion_commands_enabled',
        'motion_last_command', 'mission_geometry_enabled', 'nav_goal_tx_enabled',
        'fpga_wheel_fault', 'fpga_tof_valid', 'fpga_distance_mm',
        'fpga_hard_stop', 'detection_count', 'detections',
    )
    return {key: value.get(key) for key in keys}


def verify_candidate():
    assert sha(ARCHIVE) == EXPECTED_ARCHIVE_SHA256, 'Candidate archive hash mismatch'
    manifest_path = CANDIDATE / 'candidate-manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf8'))
    hashes = manifest['files_sha256']
    with zipfile.ZipFile(ARCHIVE) as archive:
        for member in archive.infolist():
            path = Path(member.filename)
            assert not path.is_absolute() and '..' not in path.parts, 'Unsafe archive path'
            assert not member.is_dir(), 'Unexpected directory record in archive'
            if member.filename != 'candidate-manifest.json':
                assert member.filename in hashes, 'Unmanifested archive member'
                assert sha(archive.read(member)) == hashes[member.filename], 'Archive member hash mismatch'
    for name in DEPLOY_FILES:
        assert name in hashes and sha(CANDIDATE / name) == hashes[name], f'Candidate file mismatch: {name}'
    return manifest


def merged_config(site_path, candidate_path):
    site = yaml.safe_load(site_path.read_text(encoding='utf8'))
    candidate = yaml.safe_load(candidate_path.read_text(encoding='utf8'))
    merged = copy.deepcopy(site)
    merged['perception'] = copy.deepcopy(candidate['perception'])
    merged.setdefault('target', {})['class_names'] = [f'a4_digit_{digit}' for digit in range(10)]
    merged['target'].setdefault('red_bottle', {})['enabled'] = False
    merged.setdefault('mission_geometry', {})['enabled'] = False
    assert merged['camera'] == site['camera']
    assert merged['serial'] == site['serial']
    assert merged['navigation'] == site['navigation']
    assert merged['visual_alignment'] == site['visual_alignment']
    assert not merged['serial'].get('motion_commands_enabled', False)
    return merged


def safe_runtime_preflight(value):
    assert value.get('online'), 'Vision API is not online'
    assert value.get('task_mode') == 'observe', 'Exit active task before deployment'
    assert not (value.get('mission_fpga') or {}).get('active'), 'FPGA task is active'
    assert not value.get('nav_goal_pending'), 'Navigation goal is pending'
    assert value.get('motion_commands_enabled') is False, 'Motion commands must be disabled'
    assert value.get('mission_geometry_enabled') is False, 'Experimental mission geometry must remain disabled'
    assert value.get('fpga_wheel_fault') in (0, '0'), 'Wheel fault is present'
    assert value.get('serial_connected'), 'Board telemetry is unavailable'
    assert value.get('mission_fpga_age_ms', 99999) < 2000, 'Board telemetry is stale'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--event-id', required=True)
    parser.add_argument('--deploy-safe-state-confirmed', action='store_true')
    args = parser.parse_args()
    assert args.event_id and all(char.isalnum() or char in '-_' for char in args.event_id)

    manifest = verify_candidate()
    site_config_path = ROOT / 'config/config-pi.yaml'
    candidate_config_path = CANDIDATE / 'config/config-pi.yaml'
    merged = merged_config(site_config_path, candidate_config_path)
    desired = {name: (CANDIDATE / name).read_bytes() for name in DEPLOY_FILES}
    desired['config/config-pi.yaml'] = yaml.safe_dump(merged, allow_unicode=True, sort_keys=False).encode()
    changes = {name: data for name, data in desired.items()
               if not (ROOT / name).exists() or (ROOT / name).read_bytes() != data}
    print(json.dumps({
        'candidate_revision': EXPECTED_REVISION,
        'candidate_archive_sha256': EXPECTED_ARCHIVE_SHA256,
        'candidate_file_count': len(manifest['files_sha256']),
        'changed_files': sorted(changes),
        'preserved_files': list(PRESERVE_FILES),
        'deploy_requested': args.deploy_safe_state_confirmed,
        'flash_written': False,
        'motion_api_called': False,
    }, ensure_ascii=False), flush=True)
    if not args.deploy_safe_state_confirmed:
        return 0

    assert not REPORT.exists(), 'Existing deployment report; inspect before repeating'
    before = status()
    safe_runtime_preflight(before)
    event_backup = Path('/home/pi') / f'before-r14-digit-{args.event_id}'
    event_backup.mkdir(exist_ok=False)
    old = {}
    for name in changes:
        path = ROOT / name
        if path.exists():
            old[name] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
            destination = event_backup / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
        else:
            old[name] = None
    shutil.copy2(ROOT / 'run_pi_gui.sh', event_backup / 'run_pi_gui.sh')
    (event_backup / 'service.unit').write_text(
        subprocess.check_output(['systemctl', 'cat', SERVICE], text=True), encoding='utf8')
    (event_backup / 'before-status.json').write_text(
        json.dumps(compact(before), ensure_ascii=False, indent=2), encoding='utf8')
    (event_backup / 'rollback-manifest.json').write_text(json.dumps({
        name: None if value is None else sha(value[0]) for name, value in old.items()
    }, indent=2), encoding='utf8')
    preserved = {name: sha(ROOT / name) for name in PRESERVE_FILES if (ROOT / name).exists()}
    report = {
        'event_id': args.event_id,
        'candidate_revision': EXPECTED_REVISION,
        'candidate_archive_sha256': EXPECTED_ARCHIVE_SHA256,
        'backup': str(event_backup),
        'safe_state_confirmed_by_user': True,
        'flash_written': False,
        'fpga_reconfigured': False,
        'motion_api_called': False,
        'service_changed': True,
        'preserved_sha256': preserved,
        'passed': False,
        'scope': 'R14 digit recognition software only; no physical motion or recognition acceptance',
    }
    service_stopped = False
    try:
        service('stop')
        service_stopped = True
        for name, data in changes.items():
            atomic(ROOT / name, data, old[name][1] if old[name] else 0o644)
        py = str(ROOT / '.venv/bin/python')
        for name in DEPLOY_FILES:
            if name.endswith('.py'):
                subprocess.run([py, '-m', 'py_compile', str(ROOT / name)], cwd=ROOT, check=True)
        subprocess.run([py, '-c',
            "from src.detection.factory import create_detector; "
            "d=create_detector({'perception':{'backend':'a4_digits'}}); "
            "assert d.revision=='" + EXPECTED_REVISION + "' and len(d.names)==10"],
            cwd=ROOT, check=True)
        service('start')
        service_stopped = False
        frames = []
        last_frame = None
        deadline = time.monotonic() + 75
        current = None
        while time.monotonic() < deadline:
            time.sleep(1)
            try:
                current = status()
            except (OSError, ValueError):
                continue
            if not (current.get('online')
                    and current.get('detector_backend') == 'a4_digits'
                    and current.get('detector_revision') == EXPECTED_REVISION):
                continue
            safe_runtime_preflight(current)
            if current.get('frame_id') != last_frame:
                frames.append(compact(current))
                last_frame = current.get('frame_id')
            if len(frames) >= 3:
                break
        assert len(frames) >= 3, 'No three fresh frames from the R14 service'
        assert all(sha(ROOT / name) == value for name, value in preserved.items())
        applied = yaml.safe_load(site_config_path.read_text(encoding='utf8'))
        assert applied == merged, 'Unexpected production config change'
        assert all((ROOT / name).read_bytes() == data for name, data in desired.items())
        for page in ('/', '/a4-targets.html'):
            with urllib.request.urlopen('http://127.0.0.1:8080' + page, timeout=4) as response:
                assert response.status == 200
        report.update(
            passed=True,
            frames=frames,
            live_target_detected=any(frame.get('detection_count', 0) for frame in frames),
            deployed_sha256={name: sha(ROOT / name) for name in changes},
            preserved_sha256=preserved,
            service_state=subprocess.check_output(
                ['systemctl', 'show', SERVICE, '-p', 'ActiveState', '-p', 'MainPID'], text=True),
        )
    except BaseException as error:
        report['error'] = str(error)
        if service_stopped or changes:
            service('stop')
            for name, record in old.items():
                path = ROOT / name
                if record is None:
                    if path.exists():
                        path.unlink()
                else:
                    atomic(path, record[0], record[1])
            service('start')
            report['rollback_restored'] = True
        raise
    finally:
        REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps({'passed': True, 'backup': str(event_backup), 'report': str(REPORT),
                      'status': compact(current)}, ensure_ascii=False), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
