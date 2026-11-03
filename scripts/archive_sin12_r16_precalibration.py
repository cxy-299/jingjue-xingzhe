"""Preserve the completed but not fully validated pre-calibration R16."""
from pathlib import Path
import datetime, hashlib, json, shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    hardware=json.loads((OUT/'sin12_hdmi_r16_build_sources.json').read_text(encoding='utf-8-sig'))
    software=json.loads((OUT/'sin12_hdmi_r16_software_sources.json').read_text(encoding='utf-8-sig'))
    assert all(sha(ROOT/p)==h for p,h in {**hardware,**software}.items())
    assert (OUT/'sin12_hdmi_r16_build_exit.txt').read_text().strip()=='0'
    timing=json.loads((OUT/'SIN12_R16_TIMING_INSPECTION_2026-11-01.json').read_text())
    assert timing['internal_sta_checks_pass'] and all(timing['checks'].values())
    impl=ROOT/'fpga/sin12_hdmi/impl'
    for name,record in timing['files'].items(): assert sha(impl/'pnr'/name)==record['sha256']
    dest=OUT/'sin12_hdmi_r16_precalibration_20261101_121802'
    assert not dest.exists(), 'Preserve previous archive'
    dest.mkdir();shutil.copytree(impl,dest/'impl')
    paths=set(hardware)|set(software)
    for folder in ('scripts','fpga/motor_bt_drive','tests'):
        paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT/folder).glob('*r16*') if p.is_file())
    for p in paths:
        target=dest/'sources'/p;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,target)
        assert sha(target)==sha(ROOT/p)
    for p in OUT.iterdir():
        if p.is_file() and 'r16' in p.name.lower():shutil.copy2(p,dest/p.name)
    report=dict(candidate='R16 PRECALIBRATION ONLY', fully_validated=False, mapped_validation_complete=False,
        ground_distance_calibrated=False, counts_per_100mm=1000, usercode='534E3250',
        hardware_access=False, reason='User requests R16 preliminary straight-line333 counts/100mm; preserve old build before editing',
        saved_at=datetime.datetime.now().isoformat(), timing=timing)
    (dest/'PRECALIBRATION_VERIFICATION.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    inventory={p.relative_to(dest).as_posix():sha(p) for p in dest.rglob('*') if p.is_file()}
    (dest/'ARCHIVE_SHA256.json').write_text(json.dumps(inventory,indent=2),encoding='utf-8')
    assert all(sha(dest/p)==h for p,h in inventory.items())
    print(json.dumps(dict(archive=str(dest),files=len(inventory),fully_validated=False),indent=2))
if __name__=='__main__':main()
