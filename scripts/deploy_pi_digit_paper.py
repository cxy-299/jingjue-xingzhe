"""Scoped, reversible perception deployment after explicit parked approval.

No FPGA programming, motor commands, task-mode API writes or automatic resume.
"""
import argparse
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

ROOT=Path('/home/pi/ling_shu_vision')
STAGE=Path(__file__).resolve().parent
SERVICE='ling-shu-vision-gui.service'
FILES=('src/detection/printed_digit.py','src/detection/paper_digit_assist.py')
REVISION='printed-digit-v4-paper-assist-bounded-20261101'
EXPECTED_OLD={'src/detection/printed_digit.py':'b47ec0c7cf49c45b726c688f901d8b84ad66ed03652d57e03b2bda6429da5d6f',
              'src/detection/paper_digit_assist.py':'4c7bb2ebfc0bfe3687a78d1da9431c5ac5668d4b8c2325408ee4a947fee66e0e'}


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None


def status():
    with urllib.request.urlopen('http://127.0.0.1:8080/api/status',timeout=4) as response:
        return json.load(response)


def safe(s,after=False):
    assert s.get('online') and s.get('serial_connected')
    assert not (s.get('mission_fpga') or {}).get('active'),'FPGA task active'
    assert s.get('mission_fpga_age_ms',99999)<2000,'No fresh FPGA stop acknowledgement'
    assert not s.get('nav_goal_pending') and s.get('nav_goal_tx_enabled') is False
    assert s.get('motion_commands_enabled') is False and s.get('mission_geometry_enabled') is False
    assert s.get('fpga_wheel_fault') in (0,'0')
    if after:assert s.get('task_mode')=='observe','Restart must remain idle'


def service(action):
    subprocess.run(['sudo','-n','systemctl',action,SERVICE],check=True,timeout=25)


def atomic(path,data,mode):
    with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as f:
        temporary=Path(f.name);f.write(data);f.flush();os.fsync(f.fileno())
    os.chmod(temporary,mode);os.replace(temporary,path)


def protected():
    files=[]
    for folder in ('src','config','web','assets'):
        files.extend(p for p in (ROOT/folder).rglob('*') if p.is_file()
                     and '__pycache__' not in p.parts)
    files.extend(ROOT/n for n in ('run_pi_gui.sh','run_pi.sh','scripts/build_nav_map.py'))
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(files))
            if p.exists() and p.relative_to(ROOT).as_posix() not in FILES}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--event-id',required=True)
    parser.add_argument('--apply-parked-confirmed',action='store_true');args=parser.parse_args()
    assert args.event_id and all(c.isalnum() or c in '-_' for c in args.event_id)
    native=json.loads((STAGE/'native_validation.json').read_text())
    expected={n:sha(STAGE/n) for n in FILES}
    assert native['passed'] and native['skipped']==0 and native['native_test_count']>=99
    assert native['candidate_sha256']==expected
    assert native['revision']==REVISION
    assert {n:sha(ROOT/n) for n in FILES}==EXPECTED_OLD,'Unexpected live source; inspect first'
    before=status();safe(before)
    report=dict(passed=False,candidate_sha256=expected,old_sha256=EXPECTED_OLD,
                before_status=before,native_validation_sha256=sha(STAGE/'native_validation.json'),
                revision=REVISION,changed_files=FILES,user_parked_confirmation=True,
                fpga_programmed=False,flash_written=False,motion_command_sent=False,
                task_api_called=False,automatic_resume=False)
    if not args.apply_parked_confirmed:
        print(json.dumps(report,ensure_ascii=False));return
    report_path=STAGE/(args.event_id+'_deployment_report.json');assert not report_path.exists()
    backup=Path('/home/pi')/('before-digit-paper-'+args.event_id);backup.mkdir(exist_ok=False)
    old={n:((ROOT/n).read_bytes(),stat.S_IMODE((ROOT/n).stat().st_mode))
         if (ROOT/n).exists() else None for n in FILES}
    for name,record in old.items():
        if record:
            p=backup/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,p)
    preserved=protected();unit=subprocess.check_output(['systemctl','cat',SERVICE],text=True)
    report.update(backup=str(backup),protected_sha256=preserved)
    (backup/'before_status.json').write_text(json.dumps(before,ensure_ascii=False,indent=2),encoding='utf8')
    (backup/'service.unit').write_text(unit)
    (backup/'rollback_manifest.json').write_text(json.dumps(EXPECTED_OLD,indent=2))
    try:
        safe(status())
        service('stop')
        for name in FILES:atomic(ROOT/name,(STAGE/name).read_bytes(),old[name][1] if old[name] else 0o644)
        subprocess.run([str(ROOT/'.venv/bin/python'),'-m','py_compile',*[str(ROOT/n) for n in FILES]],
                       check=True,cwd=ROOT)
        service('start');frames=[];last=None;deadline=time.monotonic()+55
        while time.monotonic()<deadline:
            time.sleep(1)
            try:current=status()
            except (OSError,ValueError):continue
            if current.get('detector_revision')!=REVISION:continue
            safe(current,after=True)
            if current.get('frame_id')!=last:
                frames.append(current);last=current.get('frame_id')
            if len(frames)>=8:break
        assert len(frames)>=8,'No eight fresh safe frames after restart'
        assert protected()==preserved,'Protected source/config changed'
        assert subprocess.check_output(['systemctl','cat',SERVICE],text=True)==unit
        assert {n:sha(ROOT/n) for n in FILES}==expected
        report.update(passed=True,frames=frames,service_state=subprocess.check_output(
            ['systemctl','show',SERVICE,'-p','ActiveState','-p','MainPID'],text=True))
    except BaseException as error:
        report['error']=str(error);service('stop')
        for name,record in old.items():
            if record:atomic(ROOT/name,*record)
            elif (ROOT/name).exists():(ROOT/name).unlink()
        service('start');report['rollback_restored']={n:sha(ROOT/n) for n in FILES}==EXPECTED_OLD
        raise
    finally:report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(dict(passed=True,backup=str(backup),report=str(report_path),
                         live_frames=len(frames),detected_frames=sum(bool(s.get('detection_count')) for s in frames)),ensure_ascii=False))


if __name__=='__main__':main()
