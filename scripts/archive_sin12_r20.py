"""Independent R20 evidence archive; failure never implies acceptance."""
from pathlib import Path
from datetime import datetime
import argparse,hashlib,json,re,shutil,zipfile,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--failure');a=ap.parse_args()
 hardware=read(OUT/'sin12_hdmi_r20_build_sources.json');software=read(OUT/'sin12_hdmi_r20_software_sources.json')
 actual={k:sha(ROOT/k) for k in hardware};report=dict(passed=False,failure=a.failure,user_code='534E3254',revision='R20/K14/REV5_ENABLE16',hardware_sources=len(hardware),software_sources=len(software),programmed=False,flash_written=False,vehicle_tested=False,whole_system_SDF=False,counts_per_cell=500,early_stop_mm=200,hard_stop_mm=100,inflate_mm=210,detour='Actual occupancy/denied-edge BFS, every next cell, original goal retained; whole-cell intersection safety coverage',limitations=['Field calibration not signed','Legacy observedE02/ToF dropout unresolved','External IO delays/MPW/ordinaryPCLK/HDMI captions unsigned','Scaled tick/ideal plant is not vehicle/SDF','No guarantee for unseen surfaces from one ToF beam'])
 assert len(hardware)==58
 if not a.failure:
  assert actual==hardware,'Build source drift'
  assert all(sha(ROOT/k)==v for k,v in software.items()),'Software source drift'
  assert (OUT/'sin12_hdmi_r20_build_exit.txt').read_text().strip()=='0'
  sta=read(OUT/'SIN12_R20_TIMING_INSPECTION_2026-11-02.json');audit=read(OUT/'SIN12_R20_CONSTRAINT_AUDIT.json')
  assert sta['internal_sta_checks_pass'] and len(sta['checks'])==16 and all(sta['checks'].values())
  assert audit['passed'] and len(audit['active_constraints'])==16 and len(audit['pixel_async_false_path_endpoints'])==2
  for n,v in sta['files'].items():assert sha(ROOT/'fpga/sin12_hdmi/impl/pnr'/n)==v['sha256']
  for n,v in audit['source_hashes'].items():assert sha(ROOT/'fpga/sin12_hdmi'/n)==v
  vg=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg';digest=sha(vg)
  mapped={k:read(OUT/('SIN12_R20_MAPPED_'+k+'_VALIDATION.json')) for k in ('TOF','TARGET','NAV')}
  for m in mapped.values():assert m['passed'] and m['netlist_sha256']==digest and m['internal_forces'] is False
  assert mapped['TOF']['checks']==91 and mapped['TARGET']['vectors']==2172
  nav=mapped['NAV'];assert nav['final_errors']==0 and nav['final_warnings'] in (0,4)
  assert nav['scenario_markers'].count('R20_MAPPED_NAV_FRACTIONAL_ADAPTIVE_GOAL_PASS')==4
  for marker in ['R20_MAPPED_NAV_854MM_REAL_DISTANCE_GRID12_ADAPTIVE_GOAL_PASS','R20_MAPPED_NAV_200MM_SUBTICK_STOP_300MM_CLEAR_ORIGINAL_GOAL_PASS','R20_MAPPED_NAV_TWO_NEW_OBSTACLES_ORIGINAL_GOAL_PASS','R20_MAPPED_NAV_SENSOR_LOSS_E02_NO_RESTART_PASS','R20_MAPPED_NAV_100MM_HARD_STOP_NO_RESTART_PASS']:
   assert marker in nav['scenario_markers'],marker
  navdir=ROOT/'tmp/sin12_r20_mapped_nav';assert sha(navdir/'mapped.v')==nav['mapped_wrapper_sha256']
  assert sha(ROOT/'fpga/motor_bt_drive/tb_sin12_r20_mapped_nav.sv')==nav['testbench_sha256']
  for kind in ('tof','target'):
   m=mapped[kind.upper()];d=ROOT/('tmp/sin12_r20_system_'+kind)
   assert sha(d/'mapped.v')==m['mapped_source_sha256'] and sha(d/'wrapper.v')==m['mapped_wrapper_sha256']
  rtl=read(OUT/'R20_RTL_VALIDATION.json');assert rtl['passed']
  for n,v in rtl['logs'].items():assert sha(OUT/n)==v
  xml=ET.parse(OUT/'r20_second_host_validation.xml');suites=xml.getroot().iter('testsuite');suites=list(suites)
  assert sum(int(s.get('tests',0)) for s in suites)==21 and all(int(s.get('failures',0))==int(s.get('errors',0))==int(s.get('skipped',0))==0 for s in suites)
  report.update(passed=True,sta=sta,constraint_audit=audit,mapped=mapped,rtl=rtl,host_tests=21,host_tests_include_real_Tk_fake_ports=True,netlist_sha256=digest,fs_sha256=sha(ROOT/'fpga/sin12_hdmi/impl/pnr/sin12_hdmi_system.fs'))
 prefix='sin12_hdmi_r20_'+('failed_'+a.failure+'_' if a.failure else '')
 dest=OUT/(prefix+datetime.now().strftime('%Y%m%d_%H%M%S'));dest.mkdir()
 if not a.failure:
  (OUT/'R20_VALIDATION.json').write_text(json.dumps(dict(report,independent_archive=str(dest)),indent=2)+'\n')
  setup_margin=sta['tables']['3.1.1 Setup Paths Table']['minimum_slack_ns']
  hold_margin=sta['tables']['3.1.2 Hold Paths Table']['minimum_slack_ns']
  handoff=f'''# R20 自适应非整格绕行离线交接

内部STA与窄例外审计实际通过：16项检查全true，58硬件源hash一致，六时钟setup/hold TNS为0，setup/hold违规0/0。控制Fmax {sta['fmax_mhz']['clk_50m']}MHz，setup最小显示裕量+{setup_margin}ns，hold +{hold_margin}ns。未降低时钟或扩大SDC例外。

同最终VG ToF91、target2172、NAV {nav['primitive_count']} primitive回归全部通过；NAV Errors0/Warnings{nav['final_warnings']}，官方SDPX9B既有警告原样保留。4方向非整格障碍、854mm外部理想plant实距投影至(17,12)、逐格扩距到原终点、两个新障碍及E02/100mm硬停不自动恢复均有实际映射证据。外部tick/理想plant缩放不是整机SDF或实车标定。

20cm触发，100mm硬停，210mm整格相交安全覆盖，500计数名义10cm。部分覆盖的当前格仅在实际停稳位置仍在210mm区外时允许安全退出，保留全部占用与禁边，不清图强行通过。不要求障碍物对齐格中心，不用手填粗略格替换实际ToF毫米投影。

UserCode534E3254/K14/REV5_ENABLE16。尚未下载本候选SRAM/Flash，当前硬件仍上次R19事件，无新读回。父R19硬件与封存档保持；任务5功能保留。用户红框指定的GUI顶部说明/0–19刻度/底部旧版文字已隐藏，当前GUI文件已更新但运行进程不热更新，agent未重启GUI。

K14配套驾驶台源码：{ROOT/'fpga/motor_bt_drive/pc_unified_console.py'}。候选目录的配套host模块支持K14；父目录当前host版本能力未扩展到K14。以后使用R20硬件须打开配套新版驾驶台，不自动连接或启动任务。

尚未解决/签核：现场ToF转向掉帧、500计数地面校准、单束ToF不可见表面、外部IO delay/MPW/普通PCLK与HDMI字幕旧缺项。实际车辆绕行效果仍需后续单独授权现场验证。

VG SHA256: {digest}

FS SHA256: {report['fs_sha256']}

独立归档：{dest}
'''
  (OUT/'R20_FINAL_HANDOFF.md').write_text(handoff,encoding='utf-8')
 impl=ROOT/'fpga/sin12_hdmi/impl'
 if impl.exists():shutil.copytree(impl,dest/'impl')
 for k in set(hardware)|set(software):
  target=dest/'sources'/k;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/k,target)
 evidence=dest/'evidence';evidence.mkdir()
 for f in list(OUT.iterdir()):
  if f.is_file() and f.suffix in ('.json','.md','.log','.xml','.txt','.do'):shutil.copy2(f,evidence/f.name)
 for f in list(OUT.glob('sin12_hdmi_r20_failed_*')):
  if f.name!=dest.name and f.is_dir():
   history=dest/'history';history.mkdir(exist_ok=True)
   with zipfile.ZipFile(history/(f.name+'.zip'),'w',compression=zipfile.ZIP_DEFLATED) as z:
    for item in f.rglob('*'):
     if item.is_file():z.write(item,item.relative_to(f).as_posix())
 for tag in ['sin12_r20_system_tof','sin12_r20_system_target','sin12_r20_mapped_nav']:
  d=ROOT/'tmp'/tag
  if d.exists():
   for name in ('mapped.v','wrapper.v','run.do','extraction.json'):
    if (d/name).exists():
     t=dest/'mapped_artifacts'/tag/name;t.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(d/name,t)
 report['current_hardware_hashes']=actual
 (dest/'BUILD_VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n')
 inv={p.relative_to(dest).as_posix():sha(p) for p in dest.rglob('*') if p.is_file()}
 (dest/'SHA256.json').write_text(json.dumps(inv,indent=2)+'\n')
 assert all(sha(dest/k)==v for k,v in read(dest/'SHA256.json').items())
 result={'passed':report['passed'],'archive':str(dest),'files':len(inv),'inventory_sha256':sha(dest/'SHA256.json')}
 (OUT/('R20_LAST_FAILURE_ARCHIVE.json' if a.failure else 'R20_FINAL_ARCHIVE_RESULT.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))
if __name__=='__main__':main()
