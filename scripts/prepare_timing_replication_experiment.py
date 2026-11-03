"""Snapshot the qualified map2613 RTL; vary only Replicate Resources in isolation."""
from pathlib import Path
import json
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'tmp/sin12_r1_replication'


def main():
    project = ROOT / 'fpga/motor_bt_drive/acg720_motor_bt_autonav.gprj'
    files = [(project.parent / f.attrib['path']).resolve() for f in ET.parse(project).findall('.//File')]
    files += [ROOT / 'fpga/nav/sin12_map.vh', project]
    hashes = {}
    for source in files:
        target = DEST / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        import hashlib
        hashes[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
    out = DEST / 'fpga/motor_bt_drive'
    script = f'''cd {out.as_posix()}
open_project {(out/project.name).as_posix()}
set_option -top_module acg720_motor_bt_autonav
set_option -user_code 534E3241
set_option -route_option 2
set_option -timing_driven 1
set_option -replicate_resources 1
run all
'''
    (out/'build_replication.tcl').write_text(script, encoding='utf-8')
    (DEST/'source_hashes.json').write_text(json.dumps(hashes, indent=2), encoding='utf-8')
    print(out/'build_replication.tcl')


if __name__ == '__main__':
    main()
