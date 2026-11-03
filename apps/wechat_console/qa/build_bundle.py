"""Build a standalone extension bundle and verify every archived byte."""
import difflib
import hashlib
import json
from pathlib import Path
import py_compile
import shutil
import zipfile
from datetime import datetime

APP=Path(__file__).resolve().parents[1]
ROOT=APP.parents[1]
OUT=ROOT/'output/submission/wechat_console_20261102'
DELIVER=OUT/'deliverables'
OUT.mkdir(parents=True,exist_ok=True);DELIVER.mkdir(exist_ok=True)

old=(APP/'qa/console_before.py').read_text('utf-8')
current=(ROOT/'fpga/motor_bt_drive/pc_unified_console.py').read_text('utf-8')
diff=''.join(difflib.unified_diff(old.splitlines(True),current.splitlines(True),fromfile='baseline/pc_unified_console.py',tofile='fpga/motor_bt_drive/pc_unified_console.py'))
(APP/'docs/desktop-integration.patch').write_text(diff,'utf-8')

files={}
def add(path):files[path.relative_to(ROOT).as_posix()]=path
for path in APP.rglob('*'):
    if not path.is_file() or '__pycache__' in path.parts or path.name in {'console_before.py','drive.png'}:continue
    if path.suffix=='.pyc':continue
    add(path)
for path in (ROOT/'fpga/motor_bt_drive').glob('pc*.py'):add(path)
for path in (ROOT/'src').rglob('*.py'):
    if '__pycache__' not in path.parts:add(path)
for name in ['scripts/build_nav_map.py','scripts/__init__.py','config/nav-map-2m.json','config/nav-map-sin12.json',
             'tests/test_r20_manual_avoid_compat.py','tests/test_task5_trigger_policy.py','tests/test_task5_digit_tof.py','tests/test_r19_console_map.py']:
    path=ROOT/name
    if path.is_file():add(path)

for rel,path in files.items():
    if path.suffix=='.py':py_compile.compile(str(path),cfile=str(OUT/'compile'/rel).replace('.py','.pyc'),doraise=True)
manifest={'created':datetime.now().isoformat(timespec='seconds'),'name':'境觉行者微信小程序驾驶台 · 电脑中转可演示版',
          'physical_hardware_used':False,'wechat_runtime_tested':False,'appid_configured':False,
          'files':{rel:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for rel,p in sorted(files.items())}}
(OUT/'SOURCE_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),'utf-8')

quick='''境觉行者 · 微信小程序驾驶台\n\n1. 解压后在微信开发者工具导入 apps/wechat_console 目录。\n2. 默认离线演示，不需要AppID/串口/机器人；先点击“启用本次控制”。\n3. 也可双击 apps/wechat_console/qa/preview.html 体验浏览器演示（不是微信运行时）。\n4. 电脑中转与真机准备见 apps/wechat_console/README.md。不要同时运行两个占用同一蓝牙口的驾驶台。\n\n真实接线保留，未在本次任务中连接任何硬件。需自己的AppID后进行微信真机联调与发布。\n'''
(DELIVER/'开始使用.txt').write_text(quick,'utf-8-sig')
shutil.copy2(APP/'README.md',DELIVER/'使用说明.md')
shutil.copy2(APP/'qa/preview.html',DELIVER/'境觉行者_小程序离线预览.html')
for name,cn in [('drive','驾驶'),('map','地图'),('vision','视觉'),('connect','连接')]:
    shutil.copy2(APP/'qa'/f'{name}-phone.png',DELIVER/f'界面预览_{cn}.png')
archive=DELIVER/'境觉行者_微信小程序驾驶台_电脑中转演示版.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for rel,p in sorted(files.items()):z.write(p,rel)
    z.writestr('SOURCE_MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2))
    z.writestr('开始使用.txt',quick)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for rel,entry in manifest['files'].items():assert hashlib.sha256(z.read(rel)).hexdigest()==entry['sha256'],rel
result={'archive':str(archive),'files':len(files)+2,'bytes':archive.stat().st_size,
        'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'manifest_verified':True}
(DELIVER/'PACKAGE_VERIFICATION.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8')
print(json.dumps(result,ensure_ascii=False))
