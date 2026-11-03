"""Pi-only verified passive tooling update. Existing site config/model unchanged."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import time
import urllib.request

ROOT = Path('/home/pi/ling_shu_vision')
FILES = {'src/core/visual_alignment.py', 'src/web_gui.py', 'web/dashboard.html'}


def status():
    with urllib.request.urlopen('http://127.0.0.1:8080/api/status', timeout=3) as r:
        return json.load(r)


def service(action):
    subprocess.run(['sudo','systemctl',action,'ling-shu-vision-gui.service'], check=True, timeout=20)


def main():
    with tarfile.open('/home/pi/pi-aim-data-20261030.tar') as tar:
        manifest = json.load(tar.extractfile('manifest.json'))
        assert set(manifest) == FILES and set(tar.getnames()) == FILES | {'manifest.json'}
        contents = {}
        for name, digest in manifest.items():
            assert tar.getmember(name).isfile()
            contents[name] = tar.extractfile(name).read()
            assert hashlib.sha256(contents[name]).hexdigest() == digest
    before = status()
    assert before.get('online') and not (before.get('mission_fpga') or {}).get('active')
    assert before.get('mission_fpga_age_ms', 99999) < 2000
    assert before.get('fpga_wheel_fault') in (0, '0')
    preserved = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
                 for name in ('config/config-pi.yaml','yolo11n.pt')}
    backup = Path('/home/pi')/('before-aim-data-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    backup.mkdir()
    for name in FILES:
        dest=backup/name; dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/name,dest)
    (backup/'status.json').write_text(json.dumps(before))
    service('stop')
    try:
        for name, data in contents.items(): (ROOT/name).write_bytes(data)
        subprocess.run([str(ROOT/'.venv/bin/python'),'-m','py_compile',
                        'src/core/visual_alignment.py','src/web_gui.py'],cwd=ROOT,check=True)
        service('start')
        after = None
        for _ in range(25):
            time.sleep(2)
            try:
                current = status()
                if current.get('online') and current.get('visual_tools_revision') == 'aim-data-v1-20261030':
                    after = current; break
            except (OSError, ValueError): pass
        assert after, 'No fresh frame from updated service'
        assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest() == h for n,h in preserved.items())
        assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest() == h for n,h in manifest.items())
        report=dict(backup=str(backup),manifest=manifest,preserved=preserved,status_after=after,
                    calibration_applied=False, model_trained=False, motion_commands_sent=False)
        (ROOT/'output/board/PI_AIM_DATA_DEPLOYMENT_20261030.json').write_text(json.dumps(report,indent=2))
        print(json.dumps({'passed':True,'backup':str(backup),'frame_id':after['frame_id']}))
    except BaseException:
        service('stop')
        for name in FILES: shutil.copy2(backup/name,ROOT/name)
        service('start')
        raise


if __name__ == '__main__': main()
