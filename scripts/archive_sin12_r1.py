"""Qualify and archive map2613 build. No programmer or hardware access."""
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PNR = ROOT / 'fpga/motor_bt_drive/impl/pnr'
BOARD = ROOT / 'output/board'
DEST = BOARD / 'sin12_r1_map2613_2026-10-27'


def main():
    fs = PNR / 'acg720_motor_bt_autonav.fs'
    tr = PNR / 'acg720_motor_bt_autonav.tr'
    report = tr.read_text(encoding='utf-8', errors='replace')
    with fs.open(encoding='ascii', errors='replace') as stream:
        header = ''.join(next(stream) for _ in range(15))
    if not re.search(r'UserCode: 0x534e3241\b', header, re.I):
        raise RuntimeError('Still an old fs: expected map2613 UserCode 0x534E3241')
    for label in ('Setup', 'Hold'):
        count = re.search(rf'<Numbers of {label} Violated Endpoints>:(\d+)', report)
        if not count or int(count[1]) != 0:
            raise RuntimeError(f'{label} timing not qualified')
    frequency = re.search(r'clk_50m\s+50\.000\(MHz\)\s+([\d.]+)\(MHz\)', report)
    if not frequency or float(frequency[1]) < 50:
        raise RuntimeError('Actual Fmax below real 50MHz clock requirement')
    if abs(tr.stat().st_mtime - fs.stat().st_mtime) > 120:
        raise RuntimeError('fs/tr timestamps do not belong to same build')
    for source in ('fpga/nav/sin12_map.vh', 'fpga/motor_bt_drive/acg720_motor_bt_autonav.v',
                   'fpga/motor_bt_drive/acg720_motor_bt_drive.v', 'fpga/motor_bt_drive/bt_autonav_packet_rx.v'):
        if (ROOT / source).stat().st_mtime > fs.stat().st_mtime:
            raise RuntimeError(f'fs older than required RTL: {source}')
    spec = json.loads((ROOT / 'config/nav-map-sin12.json').read_text(encoding='utf-8'))
    audit = json.loads((BOARD / 'sin12_map_audit.json').read_text(encoding='utf-8'))
    if spec['map_id'] != 0x2613 or audit['reachable'] != 166:
        raise RuntimeError('Wrong map revision or reachability')
    DEST.mkdir(exist_ok=True)
    sources = [fs, tr, PNR / 'acg720_motor_bt_autonav.rpt.txt', BOARD / 'sin12_sparse_build.log',
               ROOT / 'fpga/motor_bt_drive/build_sin12.tcl', ROOT / 'config/nav-map-sin12.json',
               ROOT / 'fpga/nav/sin12_map.vh', BOARD / 'sin12_map_audit.json']
    hashes = {}
    for source in sources:
        target = DEST / source.name
        shutil.copy2(source, target)
        hashes[target.name] = hashlib.sha256(target.read_bytes()).hexdigest().upper()
    info = dict(internal_timing_qualified=True, user_code='0x534E3241', map_id='0x2613',
                fmax_mhz=float(frequency[1]), setup_violations=0, hold_violations=0,
                start_reachable_cells=166, fs_timestamp=fs.stat().st_mtime,
                report_timestamp=tr.stat().st_mtime, sha256=hashes,
                hardware_downloaded=False, offground_accepted=False, ground_accepted=False)
    (DEST / 'qualification.json').write_text(json.dumps(info, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(info, indent=2))


if __name__ == '__main__':
    main()
