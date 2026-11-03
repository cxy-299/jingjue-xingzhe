"""Reproducible Pi task-six package, never replaces site configuration."""
import hashlib
import io
import json
from pathlib import Path
import tarfile


def main():
    root=Path(__file__).resolve().parents[1]
    paths=sorted((root/'src').rglob('*.py'))
    paths += [root/p for p in ('web/dashboard.html','scripts/build_nav_map.py',
        'scripts/deploy_sin11_pi.sh','scripts/build_sin11_update.py',
        'tests/test_semantic_mission.py','output/board/SIN11_MISSION_MAINTENANCE_2026-10-27.md')]
    manifest={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    output=root/'output/board/pi-sin11-mission-2026-10-27.tar'
    with tarfile.open(output,'w') as archive:
        for path in paths:
            info=archive.gettarinfo(str(path),arcname=path.relative_to(root).as_posix())
            info.mtime=0;info.uid=info.gid=0;info.uname=info.gname=''
            with path.open('rb') as stream:archive.addfile(info,stream)
        data=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
        info=tarfile.TarInfo('SIN11_PI_MANIFEST.json');info.size=len(data);info.mode=0o644
        archive.addfile(info,io.BytesIO(data))
    with tarfile.open(output) as archive:
        assert 'config/config-pi.yaml' not in archive.getnames()
        for name,expected in manifest.items():
            assert hashlib.sha256(archive.extractfile(name).read()).hexdigest()==expected,name
    digest=hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.tar.sha256').write_text(f'{digest}  {output.name}\n')
    print(output);print('files',len(paths),'sha256',digest)


if __name__=='__main__':main()
