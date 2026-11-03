"""Pi-only A4 candidate deployment. Explicit safe-state confirmation; rollback; no motion API."""
import argparse,copy,hashlib,json,os,shutil,stat,subprocess,tempfile,time,urllib.request,zipfile
from pathlib import Path
import yaml
ROOT=Path('/home/pi/ling_shu_vision')
STAGE=Path('/home/pi/ling_shu_vision_a4_stage2_20261031_141810')
CANDIDATE=STAGE/'candidate'
EXPECTED='5edd211b0675abde965f692844606868c536d4d4a3131456e32e8df1c92ca823'
SERVICE='ling-shu-vision-gui.service'
REPORT=STAGE/'deployment-report.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def status():
    with urllib.request.urlopen('http://127.0.0.1:8080/api/status',timeout=4) as r:return json.load(r)
def service(action):subprocess.run(['sudo','systemctl',action,SERVICE],check=True,timeout=25)
def atomic(path,data,mode=0o644):
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as f:
        temp=Path(f.name);f.write(data);f.flush();os.fsync(f.fileno())
    os.chmod(temp,mode);os.replace(temp,path)
def compact(s):
    keys=('online','frame_id','model','detector_backend','detector_revision','fps','resolution',
      'mission_strategy','mission_categories','task_mode','task_state','mission_fpga','mission_fpga_age_ms',
      'serial_connected','serial_frames_sent','serial_last_error','serial_last_msg_type',
      'motion_commands_enabled','motion_last_command','mission_geometry_enabled','nav_goal_tx_enabled',
      'fpga_wheel_fault','fpga_tof_valid','fpga_distance_mm','fpga_hard_stop','detection_count','detections')
    return {k:s.get(k) for k in keys}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--deploy-safe-state-confirmed',action='store_true')
    parser.add_argument('--event-id',required=True);args=parser.parse_args()
    assert all(c.isalnum() or c in '-_' for c in args.event_id)
    assert sha(STAGE/'pi_source_candidate.zip')==EXPECTED
    manifest=json.loads((CANDIDATE/'candidate-manifest.json').read_text())['files_sha256']
    with zipfile.ZipFile(STAGE/'pi_source_candidate.zip') as z:
        for member in z.infolist():
            p=Path(member.filename)
            assert not p.is_absolute() and '..' not in p.parts and not member.is_dir()
            assert (member.external_attr>>16)&0o170000!=0o120000
            if member.filename!='candidate-manifest.json':
                assert hashlib.sha256(z.read(member)).hexdigest()==manifest[member.filename]
                assert sha(CANDIDATE/member.filename)==manifest[member.filename]
    # Packaging included a map for standalone imports. Never replace the site map.
    # Reviewed live helper differs only in optional neighbor-order API; web uses the
    # unchanged three-argument call. Preserve its historical map and route behavior.
    assert sha(ROOT/'scripts/build_nav_map.py')=='682cc8df00b11bf5866b16d5e44388caa74fffb90263dc2a376294f2a8efb322', 'Reviewed site map helper changed'
    site=yaml.safe_load((ROOT/'config/config-pi.yaml').read_text())
    merged=copy.deepcopy(site)
    merged['perception']=yaml.safe_load((CANDIDATE/'config/config-pi.yaml').read_text())['perception']
    merged.setdefault('target',{})['class_names']=['a4_digit_'+str(i) for i in range(10)]
    merged['target'].setdefault('red_bottle',{})['enabled']=False
    merged.setdefault('mission_geometry',{})['enabled']=False
    assert merged['camera']==site['camera'] and merged['serial']==site['serial']
    assert merged['navigation']==site['navigation'] and merged['visual_alignment']==site['visual_alignment']
    assert not merged['serial'].get('motion_commands_enabled',False), 'Do not enable old motion stream'
    excluded={'src/core/follow_control.py','src/comm/autonav.py','src/comm/pid_tuning.py'}
    desired={str(p.relative_to(CANDIDATE)):p.read_bytes() for p in CANDIDATE.glob('src/**/*.py')
             if str(p.relative_to(CANDIDATE)) not in excluded}
    for name in ('web/dashboard.html','web/a4-targets.html','assets/a4_digits_templates.json'):
        desired[name]=(CANDIDATE/name).read_bytes()
    desired['config/config-pi.yaml']=yaml.safe_dump(merged,allow_unicode=True,sort_keys=False).encode()
    changes={n:d for n,d in desired.items() if not (ROOT/n).exists() or (ROOT/n).read_bytes()!=d}
    print(json.dumps({'changed_files':sorted(changes),'site_map_preserved':True,'deploy_requested':args.deploy_safe_state_confirmed}),flush=True)
    if not args.deploy_safe_state_confirmed:return
    assert not REPORT.exists(), 'Existing result: inspect before repeating deployment'
    before=status()
    assert before.get('online') and not (before.get('mission_fpga') or {}).get('active')
    assert before.get('mission_fpga_age_ms',99999)<2000
    assert before.get('fpga_wheel_fault') in (0,'0')
    backup=Path('/home/pi')/('before-a4-'+args.event_id);backup.mkdir(exist_ok=False)
    old={n:((ROOT/n).read_bytes(),stat.S_IMODE((ROOT/n).stat().st_mode)) if (ROOT/n).exists() else None for n in changes}
    for name,record in old.items():
        if record is not None:
            dst=backup/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,dst)
    shutil.copy2(ROOT/'run_pi_gui.sh',backup/'run_pi_gui.sh')
    (backup/'service.unit').write_text(subprocess.check_output(['systemctl','cat',SERVICE],text=True))
    (backup/'before-status.json').write_text(json.dumps(compact(before),ensure_ascii=False,indent=2))
    (backup/'rollback-manifest.json').write_text(json.dumps({n:None if v is None else hashlib.sha256(v[0]).hexdigest() for n,v in old.items()},indent=2))
    preserved={n:sha(ROOT/n) for n in ('config/nav-map-2m.json','scripts/build_nav_map.py','yolo11n.pt','run_pi_gui.sh','src/core/follow_control.py')}
    report=dict(event_id=args.event_id,candidate_sha256=EXPECTED,backup=str(backup),
      safe_state_confirmed_by_user=True,flash_written=False,fpga_reconfigured=False,
      motion_api_called=False,motion_commands_sent=False,service_changed=True,
      preserved_sha256=preserved,passed=False,scope='A4 live software and fresh camera frames; NOT physical target/ToF/motion acceptance')
    service('stop')
    try:
        for name,data in changes.items():atomic(ROOT/name,data,old[name][1] if old[name] else 0o644)
        subprocess.run([str(ROOT/'.venv/bin/python'),'-m','compileall','-q','src'],cwd=ROOT,check=True)
        subprocess.run([str(ROOT/'.venv/bin/python'),'-c',
          "import src.web_gui; from scripts.build_nav_map import load_map; from src.detection.factory import create_detector; assert load_map()['grid_cells']==20; assert len(create_detector({'perception':{'backend':'a4_digits'}}).names)==10"],cwd=ROOT,check=True)
        service('start')
        frames=[];last=None;deadline=time.monotonic()+75
        while time.monotonic()<deadline:
            time.sleep(1)
            try:current=status()
            except (OSError,ValueError):continue
            if not (current.get('online') and current.get('detector_backend')=='a4_digits'
              and current.get('detector_revision')=='a4-digit-v2-partial-20261031'):continue
            assert not (current.get('mission_fpga') or {}).get('active'), 'Unexpected active mission'
            assert current.get('task_mode')=='observe', 'Unexpected automatic task'
            assert current.get('motion_commands_enabled') is False
            assert current.get('mission_geometry_enabled') is False
            if current.get('frame_id')!=last:
                frames.append(compact(current));last=current.get('frame_id')
            if len(frames)>=3 and current.get('serial_connected') and current.get('mission_fpga_age_ms',99999)<2000:break
        assert len(frames)>=3, 'No three fresh frames from A4 live service'
        assert current.get('serial_connected') and current.get('mission_fpga_age_ms',99999)<2000, 'Board telemetry not fresh'
        assert all(sha(ROOT/n)==h for n,h in preserved.items())
        applied=yaml.safe_load((ROOT/'config/config-pi.yaml').read_text())
        assert applied==merged
        assert all((ROOT/n).read_bytes()==d for n,d in desired.items())
        for path in ('/','/a4-targets.html'):
            with urllib.request.urlopen('http://127.0.0.1:8080'+path,timeout=4) as response:assert response.status==200
        report.update(passed=True,real_camera_frames=frames,changed_sha256={n:sha(ROOT/n) for n in changes},
          preserved_config_sections=['camera','serial','navigation','visual_alignment','model','mock_fpga','display','runtime'],
          site_map_unchanged=True,service_state=subprocess.check_output(['systemctl','show',SERVICE,'-p','ActiveState','-p','MainPID'],text=True))
    except BaseException as e:
        report['error']=str(e)
        service('stop')
        for name,record in old.items():
            path=ROOT/name
            if record is None:
                if path.exists():path.unlink()
            else:atomic(path,record[0],record[1])
        service('start');report['rollback_restored']=True
        raise
    finally:
        REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({'passed':True,'backup':str(backup),'report':str(REPORT),'status':compact(current)},ensure_ascii=False),flush=True)
if __name__=='__main__':main()
