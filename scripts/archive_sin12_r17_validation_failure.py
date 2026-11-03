"""Preserve R17 full implementation/source/log evidence before validation repairs."""
from pathlib import Path
import hashlib,json,shutil,sys,datetime
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'output/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    label=sys.argv[1]
    assert label.replace('_','').isalnum()
    dest=OUT/('sin12_hdmi_r17_failed_'+label)
    assert not dest.exists(), 'Never overwrite failure evidence'
    hardware=json.loads((OUT/'sin12_hdmi_r17_build_sources.json').read_text(encoding='utf-8-sig'))
    software=json.loads((OUT/'sin12_hdmi_r17_software_sources.json').read_text(encoding='utf-8-sig'))
    assert all(sha(ROOT/p)==h for p,h in {**hardware,**software}.items())
    dest.mkdir();shutil.copytree(ROOT/'fpga/sin12_hdmi/impl',dest/'impl')
    for rel in set(hardware)|set(software):
        target=dest/'sources'/rel;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/rel,target);assert sha(target)==sha(ROOT/rel)
    for p in OUT.iterdir():
        if p.is_file() and 'r17' in p.name.lower():shutil.copy2(p,dest/p.name)
    prepared=ROOT/'tmp/sin12_r17_mapped_recovery'
    if prepared.exists():
        (dest/'mapped_recovery').mkdir()
        for name in ('extraction.json','mapped.v','run.do'):
            if (prepared/name).exists():shutil.copy2(prepared/name,dest/'mapped_recovery'/name)
    (dest/'FAILURE.json').write_text(json.dumps(dict(label=label,hardware_access=False,
        candidate_passed=False,time=datetime.datetime.now().isoformat()),indent=2))
    inventory={p.relative_to(dest).as_posix():sha(p) for p in dest.rglob('*') if p.is_file()}
    (dest/'ARCHIVE_SHA256.json').write_text(json.dumps(inventory,indent=2))
    assert all(sha(dest/p)==h for p,h in inventory.items())
    print(str(dest),len(inventory),'files verified')
if __name__=='__main__':main()
