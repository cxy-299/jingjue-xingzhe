"""Compare immutable archived failures; routing failures have no valid new STA."""
from pathlib import Path
import hashlib,json,re
from inspect_sin12_r19_timing import section

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    rounds=[]
    for number,kind,label in [(1,'sta','first'),(2,'routing','second'),(3,'routing','third'),(4,'sta','fourth'),(5,'sta','fifth'),(6,'sta','sixth'),(7,'sta','seventh'),(8,'sta','eighth')]:
        archive=next(OUT.glob(f'sin12_hdmi_r19_failed_{kind}_{label}_*'))
        evidence=json.loads((archive/'BUILD_VERIFICATION.json').read_text())
        assert evidence['passed'] is False
        config=json.loads((archive/'impl/sin12_hdmi_system_process_config.json').read_text(encoding='utf-8-sig'))
        r=dict(round=number,archive=archive.relative_to(ROOT).as_posix(),failure=kind,
               place_option=config['Place_Option'],fully_passed=False,
               nav_sha256=sha(archive/'sources/fpga/nav/autonomous_nav_guard.v'),
               mission_sha256=sha(archive/'sources/fpga/motor_bt_drive/vision_mission_guard.v'))
        if kind=='routing':
            build=(archive/'evidence/sin12_hdmi_r19_build.log').read_text(errors='replace')
            errors=[line for line in build.splitlines() if 'PR0004' in line]
            assert errors
            r.update(routing_errors=errors,new_sta_available=False,
                     stale_timing_not_reused=True)
        else:
            report_path=archive/'evidence/SIN12_R19_TIMING_INSPECTION_2026-11-01.json'
            sta=json.loads(report_path.read_text());tr_path=archive/'impl/pnr/sin12_hdmi_system.tr'
            tr=tr_path.read_text();blocks=re.split(r'\n\s*Path\d+\s*\n',section(tr,'3.3.1 Setup Analysis Report'))[1:11]
            paths=[]
            for b,old in zip(blocks,sta['top_setup_paths']):
                level=int(re.search(r'^Logic Level:\s*(\d+)',b,re.M)[1])
                arrival=b.split('Data Arrival Path:')[1].split('Data Required Path:')[0]
                arrival=arrival[arrival.index('tC2Q'):].splitlines()[1:]
                nets=[]
                for line in arrival:
                    row=line.split()
                    if len(row)>=7 and row[2]=='tNET':
                        nets.append(dict(delay_ns=float(row[1]),fanout=int(row[4]),location=row[5],node=row[6]))
                paths.append(dict(**{k:v for k,v in old.items() if k!='logic_levels'},
                    official_logic_level=level,historical_counted_cell_arcs=old.get('counted_cell_arcs',old['logic_levels']),
                    slowest_nets=sorted(nets,key=lambda n:n['delay_ns'],reverse=True)[:5]))
            r.update(new_sta_available=True,setup_violations=sta['setup_violations'],hold_violations=sta['hold_violations'],
                fmax_mhz=sta['fmax_mhz']['clk_50m'],minimum_setup_ns=sta['tables']['3.1.1 Setup Paths Table']['minimum_slack_ns'],
                resources=sta['resources'],top_paths=paths,sta_json_sha256=sha(report_path),raw_tr_sha256=sha(tr_path))
        rounds.append(r)
    assert rounds[3]['nav_sha256']==rounds[5]['nav_sha256']
    assert len({r['mission_sha256'] for r in rounds})==1
    report=dict(rounds=rounds,official_sources=[
        dict(url='https://cdn.gowinsemi.com.cn/SUG113E.pdf',document='SUG113-1.3E',sections=['4.2','4.3.1','4.3.2']),
        dict(url='https://www.gowinsemi.com/upload/database_doc/38/document/5b923e5ef105f.pdf',document='SUG113-1.1E',sections=['2.1.2','2.1.3','4.3']),
        dict(local='D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/doc/EN/SUG550-2.4E_GowinSynthesis User Guide.pdf',document='SUG550-2.4E',section='5.11 syn_maxfan',page=57)],
        findings=['The recurring mission recovery to owner/quiet path remained structurally long across1/4/5/6',
          'Same nav/mission bytes and resource counts in4/6 did not imply equivalent physical placement; routing delay rose9.994->22.863ns',
          'Round6 single fanout1 net took5.059ns; indiscriminate maxfan changes do not address that connection',
          'Round2/3 routing failures must not inherit stale previous STA',
          'Inspector historical logic_levels counted cell arcs including carry arcs, not the official Logic Level field; keep historical evidence immutable and correct new parser'],
        decision='No further layout-option-only trials. Same-cycle balanced owner mux reduced measured setup endpoints71->6 and slack-1.832->-0.311ns at fixedPlace0, but timing is NOT closed. Remaining5mission+1trim paths motivate two individually proven width candidates; keep production mission/trim SHA until the pending user decision.',
        pending='Explicit user decision on the two protected-source SHA exceptions; width candidates have no synthesis or mapped timing evidence yet')
    approval_path=OUT/'R19_PROTECTED_SOURCE_CHANGE_REQUEST.json'
    if approval_path.exists():
        approval=json.loads(approval_path.read_text())
        report['authorization_state']=approval['status']
        if approval.get('production_applied'):
            report['pending']='Current routed verification and independent archive sealing'
    closed_path=OUT/'R19_VALIDATION.json'
    if closed_path.exists():
        closed=json.loads(closed_path.read_text())
        if closed.get('passed') and Path(closed['independent_archive']).exists():
            report['closure_result']={k:closed[k] for k in ('completed_local','setup_violations','hold_violations','minimum_setup_ns','minimum_hold_ns','fmax_mhz','netlist_sha256','independent_archive','programmed','vehicle_tested')}
            report['decision']='Real STA and same-VG mapped checks passed; independent archive sealed after targeted owner mux and two expressly approved equivalent width edits'
            report['pending']=None
    (OUT/'R19_FAILURE_RETROSPECTIVE.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps([dict(round=r['round'],place=r['place_option'],setup=r.get('setup_violations'),fmax=r.get('fmax_mhz'),slack=r.get('minimum_setup_ns'),logic=r.get('top_paths',[{}])[0].get('official_logic_level')) for r in rounds],indent=2))
if __name__=='__main__':main()
