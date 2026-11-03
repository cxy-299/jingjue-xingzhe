"""Local reproducible staging package and evidence manifest (no live writes)."""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
import cv2

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board/digit_paper_settle_20261101'
STAGE=OUT/'candidate'


def main():
    files=['src/detection/printed_digit.py','src/detection/paper_digit_assist.py',
           'tests/test_digit_paper_assist.py','tests/test_r17_digit_stability.py',
           'tests/test_printed_digit_recovery.py','tests/test_printed_digit_neighbor_filter.py',
           'tests/test_a4_digit.py','output/board/r17_digit_card_raw_20261101.jpg',
           'scripts/build_a4_digit_print_page.py','src/comm/pid_tuning.py']
    files.extend(p.relative_to(ROOT).as_posix() for p in
                 (ROOT/'tests/fixtures/a4_whitewall_20261031').glob('*') if p.is_file())
    for relative in files:
        target=STAGE/relative;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/relative,target)
    for name in ('validate_digit_paper_native.py','deploy_pi_digit_paper.py'):
        shutil.copy2(ROOT/'scripts'/name,STAGE/name)
    evidence=STAGE/'evidence';evidence.mkdir(exist_ok=True)
    shutil.copy2(OUT/'camera_raw.jpg',evidence/'camera_raw.jpg')
    shutil.copy2(OUT/'live_after/raw_01.jpg',evidence/'empty_scene.jpg')
    user=Path('C:/Users/caoxi/AppData/Local/Temp/codex-clipboard-8581d49f-2cc6-4f9d-b712-d8b6b6be31cf.png')
    shutil.copy2(user,OUT/'user_screenshot.png')
    frame=cv2.imread(str(user));assert frame is not None
    # Screenshot display crop, explicitly NOT a sensor-original frame.
    cv2.imwrite(str(evidence/'user_camera_crop.jpg'),frame[135:592,114:723])
    manifest={p.relative_to(STAGE).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(STAGE.rglob('*')) if p.is_file() and '__pycache__' not in p.parts}
    (OUT/'candidate_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    with zipfile.ZipFile(OUT/'candidate.zip','w',zipfile.ZIP_DEFLATED) as z:
        for relative in manifest:z.write(STAGE/relative,relative)
    print(json.dumps(dict(files=len(manifest),zip=str(OUT/'candidate.zip'))))


if __name__=='__main__':main()
