"""Read R8 STA evidence without treating a bitstream or exit0 as signoff.

Writes an inspection JSON, not permission to download. Missing or negative
checks are explicit; source files and timing constraints are never edited.
"""
import datetime
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/board'


def section(text, title):
    found = re.search(r'^' + re.escape(title) + r'\s*\n([\s\S]*?)(?=^\d+(?:\.\d+)*\s+|\Z)', text, re.M)
    assert found, title
    return found[1]


def main():
    assert (OUT/'sin12_hdmi_r8_build_exit.txt').read_text().strip() == '0', 'Build incomplete/nonzero'
    impl = ROOT/'fpga/sin12_hdmi/impl'
    pnr = impl/'pnr'
    tr = (pnr/'sin12_hdmi_system.tr').read_text()
    rpt = (pnr/'sin12_hdmi_system.rpt.txt').read_text()
    config = json.loads((impl/'sin12_hdmi_system_process_config.json').read_text(encoding='utf-8-sig'))
    device = (pnr/'device.cfg').read_text()
    manifest_path = OUT/'sin12_hdmi_r8_build_sources.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    source_mismatches = [name for name, digest in manifest.items()
                         if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest]
    setup = int(re.search(r'<Numbers of Setup Violated Endpoints>:(\d+)', tr)[1])
    hold = int(re.search(r'<Numbers of Hold Violated Endpoints>:(\d+)', tr)[1])
    tables = {}
    for title in ['3.1.1 Setup Paths Table', '3.1.2 Hold Paths Table',
                  '3.1.3.1 Recovery Paths Table[1]', '3.1.3.2 Recovery Paths Table[2]',
                  '3.1.4.1 Removal Paths Table[1]', '3.1.4.2 Removal Paths Table[2]',
                  '3.2 Minimum Pulse Width Table']:
        content = section(tr, title)
        rows = [line.split() for line in content.splitlines() if re.match(r'^\s+\d+\s+-?\d+\.\d+\s', line)]
        tables[title] = dict(reported_paths=len(rows),
                             minimum_slack_ns=min(float(row[1]) for row in rows) if rows else None)
        if 'Table[1]' in title:
            tables[title]['endpoint_set'] = sorted({row[3] for row in rows})
    clocks = {}
    for line in section(tr, '2.2 Clock Summary').splitlines():
        row = line.split()
        if row and row[0].isdigit():
            clocks[row[1]] = dict(period_ns=float(row[3]), frequency_mhz=float(row[4].replace('MHz','')),
                                  objects=row[-1], raw=line.strip())
    fmax = {name: None for name in clocks}
    for line in section(tr, '2.3 Max Frequency Summary').splitlines():
        row = line.split()
        if row and row[0].isdigit():
            fmax[row[1]] = float(row[3].replace('(MHz)', ''))
    tns = []
    for line in section(tr, '2.4 Total Negative Slack Summary').splitlines():
        row = line.split()
        if len(row) == 4 and row[1] in ('setup', 'hold'):
            tns.append(dict(clock=row[0], analysis=row[1], tns=float(row[2]), endpoints=int(row[3])))
    top_paths = []
    blocks = re.split(r'\n\s*Path\d+\s*\n', section(tr, '3.3.1 Setup Analysis Report'))[1:11]
    for block in blocks:
        item = {name: re.search(r'^' + name + r'\s*:\s*(.*)$', block, re.M)[1].strip()
                for name in ('Slack', 'From', 'To')}
        arrival = block.split('Data Arrival Path:')[1].split('Data Required Path:')[0]
        # Exclude the input clock tree. Data path begins at tC2Q.
        lines = arrival.splitlines()
        first = next((i for i, line in enumerate(lines) if re.search(r'\stC2Q\s', line)), len(lines))
        data = lines[first:]
        sums = {'tNET': 0., 'tCELL': 0.}
        max_fanout = 0
        levels = 0
        for line in data:
            row = line.split()
            if len(row) >= 5 and row[2] in ('tNET', 'tINS', 'tCELL', 'tC2Q'):
                if row[2] == 'tNET': sums['tNET'] += float(row[1])
                if row[2] in ('tINS', 'tCELL'):
                    sums['tCELL'] += float(row[1])
                    levels += 1
                if row[4].isdigit():
                    max_fanout = max(max_fanout, int(row[4]))
        item.update(logic_levels=levels, tNET_ns=round(sums['tNET'], 3),
                    tCELL_ns=round(sums['tCELL'], 3), maximum_data_fanout=max_fanout)
        top_paths.append(item)
    resources = {}
    for name in ('Logic', 'Register', 'BSRAM', 'DSP'):
        m = re.search(r'^\s*' + name + r'\s*\|\s*([\d.]+)', rpt, re.M)
        resources[name] = float(m[1]) if m else None
    elapsed = re.search(r'Total Time and Memory Usage:.*Elapsed time = ([^,\n]+)', rpt)[1].strip()
    filenames = ['sin12_hdmi_system.fs', 'sin12_hdmi_system.tr', 'sin12_hdmi_system.rpt.txt', 'device.cfg']
    files = {name: dict(modified_local=datetime.datetime.fromtimestamp((pnr/name).stat().st_mtime).isoformat(),
                        bytes=(pnr/name).stat().st_size, sha256=hashlib.sha256((pnr/name).read_bytes()).hexdigest(),
                        newer_than_manifest=(pnr/name).stat().st_mtime >= manifest_path.stat().st_mtime)
             for name in filenames}
    old_sdc = OUT/'sin12_hdmi_r7_20261029_223718/sources/fpga/sin12_hdmi/sin12_hdmi_system.sdc'
    unchanged_sdc = old_sdc.read_bytes() == (ROOT/'fpga/sin12_hdmi/sin12_hdmi_system.sdc').read_bytes()
    checks = dict(sources_match=not source_mismatches, setup_zero=setup == 0, hold_zero=hold == 0,
                  every_clock_tns_zero=len(tns) == 12 and all(x['tns'] == 0 and x['endpoints'] == 0 for x in tns),
                  six_clocks=set(clocks) == {'clk_50m','camera_pclk','camera_pixel','camera_serial_raw','camera_serial','camera_xclk'},
                  true_frequencies=all(abs(clocks.get(n,{}).get('frequency_mhz',0)-v)<.01
                                       for n,v in {'clk_50m':50,'camera_pclk':75.002,'camera_pixel':75,'camera_serial_raw':375,'camera_serial':375,'camera_xclk':25}.items()),
                  clocks_meet_fmax=all(fmax.get(n,0) and fmax[n] >= clocks[n]['frequency_mhz'] for n in ('clk_50m','camera_pclk','camera_pixel')),
                  positive_reported_slacks=all(t['minimum_slack_ns'] is not None and t['minimum_slack_ns'] > 0 for t in tables.values()),
                  serializer_rec_rem_coverage=all(tables[t]['reported_paths'] == 12 and len(tables[t]['endpoint_set']) == 4 for t in ('3.1.3.1 Recovery Paths Table[1]','3.1.4.1 Removal Paths Table[1]')),
                  global_rec_rem_coverage=all(tables[t]['reported_paths'] >= 200 for t in ('3.1.3.2 Recovery Paths Table[2]','3.1.4.2 Removal Paths Table[2]')),
                  sdc_unchanged=unchanged_sdc, current_files=all(f['newer_than_manifest'] for f in files.values()),
                  route2_timing1=config.get('Route_Option') == '2' and config.get('Run_Timing_Driven') is True,
                  gpio_release=config.get('SSPI') is True and config.get('JTAG') is False and config.get('MSPI') is False,
                  device_release='set SSPI regular_io = true' in device and 'set JTAG regular_io = false' in device and 'set MSPI regular_io = false' in device,
                  usercode='0x534E3248' in device and str(config.get('USERCODE')).upper().replace('0X','') == '534E3248')
    report = dict(candidate='SIN12 R8', usercode='534E3248', hardware_access=False,
                  setup_violations=setup, hold_violations=hold, checks=checks, sources_verified=len(manifest),
                  source_mismatches=source_mismatches, tables=tables, clocks=clocks, fmax_mhz=fmax, tns=tns,
                  top_setup_paths=top_paths, resources=resources, pnr_elapsed=elapsed, files=files,
                  internal_sta_checks_pass=all(checks.values()), full_external_timing_signoff=False,
                  limitations=['MPW coverage incomplete','PR1014 PCLK ordinary entry','External DVP timing not signed','HDMI sensor text OSD absent'],
                  note='Inspection only: manually inspect reset exceptions, unconstrained IO, mapped regressions before archiving as candidate.')
    (OUT/'SIN12_R8_TIMING_INSPECTION_2026-10-30.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('setup_violations','hold_violations','checks','fmax_mhz','tables','resources','pnr_elapsed','top_setup_paths')}, indent=2))


if __name__ == '__main__':
    main()
