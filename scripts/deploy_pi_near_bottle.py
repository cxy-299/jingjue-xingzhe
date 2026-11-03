"""Run ON PI: verified four-file vision update with backup/rollback; no motion API."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request


ROOT=Path('/home/pi/ling_shu_vision')
ARCHIVE=Path('/home/pi/pi-near-bottle-20261030.tar')
EXPECTED={'src/core/messages.py','src/detection/yolo_detector.py','src/web_gui.py','web/dashboard.html'}
SERVICE='ling-shu-vision-gui.service'


def status():
    with urllib.request.urlopen('http://127.0.0.1:8080/api/status',timeout=3) as response:
        return json.load(response)


def service(action):
    subprocess.run(['sudo','systemctl',action,SERVICE],check=True,timeout=20)


def main():
    assert ROOT.is_dir()
    with tarfile.open(ARCHIVE) as tar:
        manifest=json.load(tar.extractfile('PI_NEAR_BOTTLE_MANIFEST.json'))
        assert set(manifest)==EXPECTED
        assert set(tar.getnames())==EXPECTED|{'PI_NEAR_BOTTLE_MANIFEST.json'}
        content={}
        for name,wanted in manifest.items():
            member=tar.getmember(name)
            assert member.isfile() and not member.issym() and '..' not in Path(name).parts
            data=tar.extractfile(name).read()
            assert hashlib.sha256(data).hexdigest()==wanted
            content[name]=data
    before=status()
    assert before.get('online')
    board=before.get('mission_fpga') or {}
    assert not board.get('active'), 'Active board mission: do not restart vision service'
    assert before.get('mission_fpga_age_ms',99999)<2000, 'Board stop evidence is stale'
    assert before.get('fpga_wheel_fault') in ('0',0), 'Inspect existing wheel fault first'
    backup=Path('/home/pi')/('before-near-bottle-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    backup.mkdir()
    config_before=hashlib.sha256((ROOT/'config/config-pi.yaml').read_bytes()).hexdigest()
    model_before=hashlib.sha256((ROOT/'yolo11n.pt').read_bytes()).hexdigest()
    for name in EXPECTED:
        dest=backup/name;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/name,dest)
    (backup/'before_status.json').write_text(json.dumps(before,ensure_ascii=False,indent=2))
    print('Backup:',backup,flush=True)
    service('stop')
    try:
        for name,data in content.items():(ROOT/name).write_bytes(data)
        subprocess.run([str(ROOT/'.venv/bin/python'),'-m','py_compile',
            'src/core/messages.py','src/detection/yolo_detector.py','src/web_gui.py'],cwd=ROOT,check=True)
        service('start')
        after=None
        for _ in range(35):
            time.sleep(2)
            try:
                current=status()
                if current.get('online') and current.get('detector_revision')=='near-bottle-v1-20261030':
                    after=current;break
            except (OSError,ValueError):pass
        assert after, 'Updated vision failed to produce real frames'
        assert hashlib.sha256((ROOT/'config/config-pi.yaml').read_bytes()).hexdigest()==config_before
        assert hashlib.sha256((ROOT/'yolo11n.pt').read_bytes()).hexdigest()==model_before
        assert all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest for name,digest in manifest.items())
        report=dict(passed=True,backup=str(backup),manifest=manifest,
                    site_config_sha256=config_before,model_sha256=model_before,
                    motion_commands_sent=False,fpga_programmed=False,status_after=after)
        (ROOT/'output/board/PI_NEAR_BOTTLE_DEPLOYMENT_20261030.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print('Deployed; real camera frame and revision verified. No motion commands.',flush=True)
    except BaseException:
        service('stop')
        for name in EXPECTED:shutil.copy2(backup/name,ROOT/name)
        service('start')
        print('Rollback restored previous vision files.',file=sys.stderr,flush=True)
        raise


if __name__=='__main__':main()
