"""Pi-only isolated staging test. Never opens camera/serial or touches service."""
import hashlib,json,os,sys,time,zipfile,compileall
from pathlib import Path

stage=Path(sys.argv[1]).resolve()
archive=stage/'pi_source_candidate.zip'
expected=sys.argv[2]
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected
candidate=stage/'candidate'
assert not candidate.exists(), 'Refuse to overwrite an existing staging checkout'
with zipfile.ZipFile(archive) as z:
    manifest=json.loads(z.read('candidate-manifest.json'))
    for member in z.infolist():
        path=Path(member.filename)
        assert not path.is_absolute() and '..' not in path.parts and not member.is_dir()
        assert (member.external_attr>>16)&0o170000!=0o120000, 'No symlinks allowed'
        if member.filename!='candidate-manifest.json':
            assert hashlib.sha256(z.read(member)).hexdigest()==manifest['files_sha256'][member.filename]
    z.extractall(candidate)
assert compileall.compile_dir(candidate/'src',quiet=1)
os.chdir(candidate);sys.path.insert(0,str(candidate))
import cv2,numpy
from src.detection.factory import create_detector
from src.web_gui import DashboardState
from src.core.a4_targets import CLASS_BASE
from src.detection.mission_geometry import MissionGeometryReporter
from scripts.build_nav_map import load_map
assert load_map()['grid_cells']==20
full=cv2.imread(str(stage/'full.png'));partial=cv2.imread(str(stage/'partial.png'));cut=cv2.imread(str(stage/'cut.png'))
assert all(x is not None for x in (full,partial,cut))
detector=create_detector({'perception':{'backend':'a4_digits'}})
state=DashboardState();state.model_classes=detector.names
state.prepare_mission('a4_digit_2')
start=time.monotonic()
for i in range(6):target,_,task,_=state.process_detections(detector.detect(full),i,full)
assert target.class_id==CLASS_BASE+2 and task['task_target_confirmed']
full_ms=(time.monotonic()-start)*1000/6
token=task['task_lock_id'];out=detector.detect(partial)
assert len(out)==1 and out[0].source=='a4_partial_digit'
target,_,task,_=state.process_detections(out,7,partial)
assert target and task['task_lock_id']==token and task['task_target_confirmed']
assert not detector.detect(cut)
blank=numpy.full_like(full,255)
target,_,task,_=state.process_detections(detector.detect(blank),8,blank)
assert target is None and not task['task_target_confirmed']
assert MissionGeometryReporter.from_config({}) is None
report=dict(passed=True,scope='synthetic full/partial/cut/blank on Pi native OpenCV; NOT camera or field acceptance',
 hardware_access=False,camera_opened=False,serial_opened=False,service_changed=False,
 python=sys.version.split()[0],opencv=cv2.__version__,numpy=numpy.__version__,
 mean_synthetic_full_pipeline_ms=round(full_ms,2),candidate_archive_sha256=expected,
 staged_path=str(candidate),deployed_to_live_service=False)
(stage/'stage-report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print(json.dumps(report))

