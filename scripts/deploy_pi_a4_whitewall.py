"""Pi A4-only white-wall regression and one-file reversible deployment. No motion API."""
import argparse,hashlib,importlib.util,json,os,shutil,subprocess,sys,tempfile,time,urllib.request
from pathlib import Path
import numpy as np
import cv2
ROOT=Path('/home/pi/ling_shu_vision')
SERVICE='ling-shu-vision-gui.service'
REVISION='a4-digit-v3-whitewall-20261031'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def status():
    with urllib.request.urlopen('http://127.0.0.1:8080/api/status',timeout=4) as r:return json.load(r)
def main():
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True)
    p.add_argument('--deploy-safe-state-confirmed',action='store_true');args=p.parse_args()
    stage=args.stage.resolve();manifest=json.loads((stage/'manifest.json').read_text())
    for name,digest in manifest.items():assert sha(stage/name)==digest,name
    os.chdir(ROOT);sys.path.insert(0,str(ROOT))
    spec=importlib.util.spec_from_file_location('a4_whitewall_candidate',stage/'a4_digit.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    from src.detection.a4_digit import A4DigitDetector as Baseline
    from src.web_gui import DashboardState
    def candidate():
        return module.A4DigitDetector({'templates':str(ROOT/'assets/a4_digits_templates.json')})
    checks=[]
    for name in ('raw_zero.jpg','user_zero.png'):
        frame=cv2.imread(str(stage/name));assert frame is not None
        baseline=Baseline().detect(frame)
        d=candidate();times=[]
        for _ in range(8):
            started=time.monotonic();out=d.detect(frame);times.append((time.monotonic()-started)*1000)
            assert len(out)==1 and out[0].class_id==module.CLASS_BASE and out[0].source=='a4_digit_template'
        assert not candidate().detect(cv2.rotate(frame,cv2.ROTATE_180))
        assert not candidate().detect(frame[:390])
        blank=frame.copy();blank[267:373,278:357]=190
        assert not candidate().detect(blank)
        missing=frame.copy()
        if name=='raw_zero.jpg':missing[218:234,389:403]=185
        else:missing[217:232,376:390]=185
        assert not candidate().detect(missing)
        checks.append(dict(fixture=name,baseline_detections=len(baseline),candidate_score=out[0].confidence,
          mean_inference_ms=round(float(np.mean(times)),2),sample_max_inference_ms=round(max(times),2)))
    original=Path('/home/pi/ling_shu_vision_a4_stage2_20261031_141810')
    full=cv2.imread(str(original/'full.png'));partial=cv2.imread(str(original/'partial.png'));cut=cv2.imread(str(original/'cut.png'))
    d=candidate();s=DashboardState();s.model_classes=d.names;s.prepare_mission('a4_digit_2')
    for i in range(6):target,_,task,_=s.process_detections(d.detect(full),i,full)
    assert target and task['task_target_confirmed'];token=task['task_lock_id']
    out=d.detect(partial);assert len(out)==1 and out[0].source=='a4_partial_digit'
    target,_,task,_=s.process_detections(out,7,partial)
    assert target and task['task_target_confirmed'] and task['task_lock_id']==token
    assert not d.detect(cut)
    target,_,task,_=s.process_detections(d.detect(np.full_like(full,255)),8)
    assert target is None and not task['task_target_confirmed']
    report=dict(passed=True,opencv=cv2.__version__,numpy=np.__version__,field_fixture_checks=checks,
       full_to_partial_same_identity=True,partial_cut_and_blank_rejected=True,
       stage_only=True,motion_commands_sent=False,flash_written=False,service_changed=False,
       candidate_sha256=manifest['a4_digit.py'],scope='Two frozen field misses and synthetic partial sequence, not broad field acceptance')
    (stage/'stage-report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report),flush=True)
    if not args.deploy_safe_state_confirmed:return
    assert not (stage/'deployment-report.json').exists(),'Do not repeat a completed deployment'
    before=status();assert before.get('online') and before.get('detector_backend')=='a4_digits'
    assert not (before.get('mission_fpga') or {}).get('active')
    assert before.get('mission_fpga_age_ms',99999)<2000 and before.get('fpga_wheel_fault') in (0,'0')
    target=ROOT/'src/detection/a4_digit.py';backup=stage/'before_a4_digit.py'
    assert not backup.exists();shutil.copy2(target,backup)
    old_hash=sha(backup)
    preserved={n:sha(ROOT/n) for n in ('config/config-pi.yaml','src/web_gui.py','web/dashboard.html',
      'src/core/follow_control.py','scripts/build_nav_map.py','config/nav-map-2m.json','yolo11n.pt')}
    def service(action):subprocess.run(['sudo','systemctl',action,SERVICE],check=True,timeout=25)
    def install(data):
        with tempfile.NamedTemporaryFile(dir=target.parent,delete=False) as f:
            temporary=Path(f.name);f.write(data);f.flush();os.fsync(f.fileno())
        os.chmod(temporary,0o644);os.replace(temporary,target)
    event=dict(passed=False,candidate_sha256=manifest['a4_digit.py'],previous_sha256=old_hash,
      backup=str(backup),safe_state_confirmed_by_user=True,service_changed=True,
      motion_api_called=False,motion_commands_sent=False,fpga_programmed=False,flash_written=False,
      preserved_sha256=preserved,scope='One perception module only, no controller or threshold changes')
    service('stop')
    try:
        install((stage/'a4_digit.py').read_bytes())
        subprocess.run([str(ROOT/'.venv/bin/python'),'-m','py_compile',str(target)],cwd=ROOT,check=True)
        service('start');frames=[];last=None;deadline=time.monotonic()+60
        while time.monotonic()<deadline:
            time.sleep(1)
            try:current=status()
            except (OSError,ValueError):continue
            if not current.get('online') or current.get('detector_revision')!=REVISION:continue
            assert current.get('motion_commands_enabled') is False
            assert current.get('mission_geometry_enabled') is False
            assert not (current.get('mission_fpga') or {}).get('active')
            if current.get('frame_id')!=last:
                last=current.get('frame_id')
                frames.append({k:current.get(k) for k in ('frame_id','fps','detector_ms','detector_revision',
                  'detections','task_mode','mission_fpga','mission_fpga_age_ms','fpga_tof_valid','fpga_hard_stop')})
            if len(frames)>=3 and current.get('serial_connected') and current.get('mission_fpga_age_ms',99999)<2000:break
        assert len(frames)>=3 and current.get('serial_connected') and current.get('mission_fpga_age_ms',99999)<2000
        assert all(sha(ROOT/n)==h for n,h in preserved.items())
        assert sha(target)==manifest['a4_digit.py']
        event.update(passed=True,live_frames=frames,service_state=subprocess.check_output(['systemctl','show',SERVICE,'-p','ActiveState','-p','MainPID','-p','NRestarts'],text=True))
    except BaseException as error:
        event['error']=str(error);service('stop');install(backup.read_bytes());service('start')
        event['rollback_restored']=True;raise
    finally:(stage/'deployment-report.json').write_text(json.dumps(event,ensure_ascii=False,indent=2))
    print(json.dumps(event,ensure_ascii=False),flush=True)
if __name__=='__main__':main()
