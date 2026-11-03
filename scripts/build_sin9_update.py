"""Build the reproducible Pi SIN9 update without replacing site configuration."""
import hashlib
import argparse
import io
import json
from pathlib import Path
import tarfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='output/board/pi-sin9-selected-target-2026-10-26.tar')
    args = parser.parse_args()
    paths = sorted(p for p in (root / 'src').rglob('*.py') if '__pycache__' not in p.parts)
    paths += [root / rel for rel in (
        'web/dashboard.html',
        'scripts/build_nav_map.py',
        'scripts/configure_sin9_pi.py',
        'scripts/build_sin9_update.py',
        'config/nav-map-2m.json',
        'fpga/motor_bt_drive/pc_unified_model.py',
        'tests/test_locked_target_chain.py',
        'tests/fixtures/sin9_hand_histograms.json',
        'tests/test_task56_ui.js',
        'tests/test_serial_link.py',
        'output/board/SIN9_SELECTED_TARGET_MAINTENANCE_2026-10-26.md',
        'output/board/SIN9_LOCK_REACQUIRE_UPDATE_2026-10-27.md',
        'output/board/SIN9_PICK_REACQUIRE_V2_2026-10-27.md',
    )]
    manifest = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in paths}
    output = root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, 'w') as archive:
        for path in paths:
            info = archive.gettarinfo(str(path), arcname=path.relative_to(root).as_posix())
            # Avoid future timestamp warnings on the Pi's currently slow clock.
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            with path.open('rb') as stream:
                archive.addfile(info, stream)
        data = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
        info = tarfile.TarInfo('SIN9_PI_MANIFEST.json')
        info.size = len(data)
        info.mode = 0o644
        archive.addfile(info, io.BytesIO(data))
    with tarfile.open(output) as archive:
        for name, expected in manifest.items():
            assert hashlib.sha256(archive.extractfile(name).read()).hexdigest() == expected, name
        assert 'config/config-pi.yaml' not in archive.getnames()
    print(output)
    print('Files:', len(manifest), 'SHA256:', hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
