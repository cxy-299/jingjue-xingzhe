"""Read-only analysis of sparse R4 C/K telemetry; never opens a serial port."""
import argparse
import json
import re
import statistics
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from src.comm.pid_tuning import parse_pid_status, parse_wheel_sample


def analyze(path, latest_connection=True):
    raw = path.read_bytes()
    content = raw.decode('utf-16' if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig', errors='replace')
    lines = content.splitlines()
    starts = [n for n, line in enumerate(lines) if '9600/8N1 已打开' in line]
    lines = lines[starts[-1]:] if starts and latest_connection else lines
    gains = None
    sensor = None
    samples, faults, alarms, gain_events, trip_evidence = [], [], [], [], []
    last_time = None
    connection = 0
    tx_windows, active_tx = [], None
    for line in lines:
        m = re.match(r'\[([^]]+)\] (.*)', line)
        if not m:
            continue
        try:
            stamp = datetime.fromisoformat(m[1])
        except ValueError:
            continue
        last_time = m[1]
        message = m[2]
        if '9600/8N1 已打开' in message:
            if active_tx:
                tx_windows.append(dict(active_tx, stop=None, end_reason='reconnection'))
                active_tx = None
            connection += 1
            gains = sensor = None
        tx = re.match(r"TX完成: b'([FBS])'", message)
        if tx:
            letter = tx[1]
            if active_tx and (letter != active_tx['direction'] or stamp.timestamp()-active_tx['last_refresh_seconds'] > 0.4):
                tx_windows.append(dict(active_tx, stop=m[1] if letter == 'S' else None,
                    end_reason='S written' if letter == 'S' else 'direction change or refresh gap'))
                active_tx = None
            if letter in ('F', 'B'):
                if active_tx is None:
                    active_tx = dict(start=m[1], start_seconds=stamp.timestamp(), direction=letter, connection=connection)
                active_tx.update(last_refresh=m[1], last_refresh_seconds=stamp.timestamp())
        if not message.startswith('RX: '):
            continue
        payload = message[4:]
        k = parse_pid_status(payload)
        if k:
            new = (k['p'], k['i'], k['d'])
            if new != gains:
                gain_events.append({'time': m[1], 'gains': new, 'status': k['status']})
            gains = new
        s = re.fullmatch(r'I([01]) T([01]) D(\d+) H([01]) F([0-9A-Fa-f]+) R\S+ P\S+ Y\S+ W([0-9A-Fa-f]+)', payload)
        if s:
            sensor = dict(time=m[1], imu=int(s[1]), tof=int(s[2]), distance_mm=int(s[3]), hard_stop=int(s[4]), flags=int(s[5], 16), wheel_fault=int(s[6], 16))
            if sensor['wheel_fault']:
                faults.append({'time': m[1], 'frame': payload})
        # M.F is the shared alarm (led_o[5]), not that wheel's PI fault.
        # Dedicated I.W bits and X evidence identify actual PI trips.
        if re.fullmatch(r'M[1-4] .* F[1-9A-Fa-f][0-9A-Fa-f]*(?: E[1-7] X[+-]\d{3} P\d{4})?', payload):
            alarms.append({'time': m[1], 'frame': payload})
        evidence = re.fullmatch(r'M([1-4]) T\d{3} A[+-]\d{3} D\d{4} F[01] E([1-7]) X([+-]\d{3}) P(\d{4})', payload)
        if evidence:
            wheel, reason, speed, duty = map(int, evidence.groups())
            record = dict(wheel=wheel, reason=reason, speed=speed, duty=duty)
            if not any(all(old[k] == v for k,v in record.items()) for old in trip_evidence):
                trip_evidence.append(dict(record, time=m[1]))
        if payload.startswith('X'):
            faults.append({'time': m[1], 'frame': payload})
        c = parse_wheel_sample(payload)
        if c:
            samples.append(dict(c, time=m[1], seconds=stamp.timestamp(), gains=gains, sensor=sensor, connection=connection))
    groups = []
    for c in samples:
        key = (c['gains'], c['command'], c['targets'], c['connection'])
        if not groups or groups[-1]['key'] != key or c['seconds'] - groups[-1]['samples'][-1]['seconds'] > 2.5:
            groups.append({'key': key, 'samples': []})
        groups[-1]['samples'].append(c)
    segments = []
    for group in groups:
        values = group['samples']
        first = values[0]
        if not first['command'] or not any(first['targets']):
            continue
        # Drop first received snapshot after each observed transition; a C frame
        # arrives about every 1.2 s, so this is only a steady-state comparison.
        steady = values[1:]
        wheels = []
        for wheel in range(4):
            speeds = [v['speeds'][wheel] for v in steady]
            duties = [v['duties'][wheel] for v in steady]
            target = first['targets'][wheel]
            wheels.append(dict(wheel=wheel+1, target=target,
                speed_mean=round(statistics.mean(speeds), 2) if speeds else None,
                speed_min=min(speeds) if speeds else None,
                speed_max=max(speeds) if speeds else None,
                mae=round(statistics.mean(abs(s-target) for s in speeds), 2) if speeds else None,
                duty_mean=round(statistics.mean(duties), 1) if duties else None))
        distances = [v['sensor']['distance_mm'] for v in values if v['sensor']]
        segments.append(dict(start=first['time'], end=values[-1]['time'], gains=first['gains'],
            command=first['command'], snapshots=len(values), steady_snapshots=len(steady),
            observed_duration_s=round(values[-1]['seconds']-first['seconds'], 2),
            tof_range_mm=[min(distances), max(distances)] if distances else None,
            max_abs_heading_error_deg=round(max(abs(v['error_deg']) for v in values), 2), wheels=wheels))
    intervals = [b['seconds']-a['seconds'] for a,b in zip(samples, samples[1:])]
    if active_tx:
        tx_windows.append(dict(active_tx, stop=None, end_reason='no S observed yet'))
    command_trials = []
    for window in tx_windows:
        end_seconds = datetime.fromisoformat(window['stop']).timestamp() if window['stop'] else window['last_refresh_seconds']
        cmd = 1 if window['direction'] == 'F' else 2
        captured = [c for c in samples if c['connection'] == window['connection'] and c['command'] == cmd
            and window['start_seconds'] <= c['seconds'] <= end_seconds+0.15]
        command_trials.append(dict(start=window['start'], stop=window['stop'], direction=window['direction'],
            tx_duration_s=round(end_seconds-window['start_seconds'], 3), end_reason=window['end_reason'],
            c_snapshots=len(captured), gains_observed=sorted({tuple(c['gains']) for c in captured if c['gains']}),
            first_c=captured[0]['time'] if captured else None, last_c=captured[-1]['time'] if captured else None))
    runs = []
    for c in samples:
        key = (c['connection'], c['gains'], c['command'], c['reference_deg'] if c['heading_locked'] else None)
        if not runs or runs[-1]['key'] != key or c['seconds']-runs[-1]['samples'][-1]['seconds'] > 2.5:
            runs.append(dict(key=key, samples=[]))
        runs[-1]['samples'].append(c)
    movement_runs = []
    for run in runs:
        vals = run['samples']
        first, last = vals[0], vals[-1]
        if not first['command']:
            continue
        movement_runs.append(dict(start=first['time'], end=last['time'], gains=first['gains'],
            command=first['command'], snapshots=len(vals), reference_deg=round(first['reference_deg'], 2),
            first_error_deg=round(first['error_deg'], 2), last_error_deg=round(last['error_deg'], 2),
            peak_abs_error_deg=round(max(abs(v['error_deg']) for v in vals), 2),
            correction_range=[min(v['correction'] for v in vals), max(v['correction'] for v in vals)],
            last_targets=last['targets'], last_speeds=last['speeds'],
            wheel_speed_mean=[round(statistics.mean(v['speeds'][i] for v in vals), 2) for i in range(4)],
            wheel_target_mean=[round(statistics.mean(v['targets'][i] for v in vals), 2) for i in range(4)],
            diagonal_speed_residual=round(statistics.mean((v['speeds'][0]+v['speeds'][3]-v['speeds'][1]-v['speeds'][2])/4 for v in vals), 3),
            wheel_mae=[round(statistics.mean(abs(v['speeds'][i]-v['targets'][i]) for v in vals), 2) for i in range(4)]))
    return dict(log=str(path), last_log_time=last_time, gains=gains, latest_sensor=sensor,
        c_snapshot_count=len(samples), median_c_interval_s=round(statistics.median(intervals), 3) if intervals else None,
        gain_events=gain_events, fault_frames=faults, shared_alarm_frames=alarms, trip_evidence=trip_evidence, segments=segments, movement_runs=movement_runs,
        manual_command_trials=command_trials,
        latest_samples=[{k:v for k,v in s.items() if k!='seconds'} for s in samples[-5:]],
        limitation='C samples are simultaneous across wheels but sparsely transmitted; no 100 Hz transient/overshoot or ground traction verdict.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', nargs='?', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--all-connections', action='store_true')
    args = parser.parse_args()
    log = args.log or max((ROOT/'output/board/logs').glob('console_*.log'), key=lambda p:p.stat().st_mtime)
    result = analyze(log, latest_connection=not args.all_connections)
    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(rendered+'\n', encoding='utf-8')
    print(rendered)
