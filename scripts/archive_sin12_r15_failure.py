"""Archive one failed R15 build before changing sources; never authorizes programming."""
from pathlib import Path
import datetime, hashlib, json, shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board'
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    report=json.loads((OUT/'SIN12_R15_TIMING_INSPECTION_2026-10-31.json').read_text())
    assert report['internal_sta_checks_pass'] is False
    manifest=json.loads((OUT/'sin12_hdmi_r15_build_sources.json').read_text())
    assert all(digest(ROOT/p)==h for p,h in manifest.items())
    impl=ROOT/'fpga/sin12_hdmi/impl'
    stamp=datetime.datetime.fromtimestamp((impl/'pnr/sin12_hdmi_system.fs').stat().st_mtime).strftime('%Y%m%d_%H%M%S')
    dest=OUT/f'sin12_hdmi_r15_failed_sta_{stamp}'
    assert not dest.exists(), 'Preserve existing evidence'
    dest.mkdir()
    shutil.copytree(impl,dest/'impl')
    for p in manifest:
        target=dest/'sources'/p
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/p,target)
        assert digest(target)==manifest[p]
    for p in OUT.iterdir():
        if p.is_file() and ('r15' in p.name.lower()): shutil.copy2(p,dest/p.name)
    inventory={str(p.relative_to(dest)):digest(p) for p in dest.rglob('*') if p.is_file()}
    (dest/'ARCHIVE_SHA256.json').write_text(json.dumps(inventory,indent=2),encoding='utf-8')
    assert all(digest(dest/p)==h for p,h in inventory.items())
    print(json.dumps(dict(archive=str(dest),files=len(inventory),setup=report['setup_violations'],hold=report['hold_violations'],download_permitted=False),indent=2))
if __name__=='__main__':main()
