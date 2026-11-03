"""Read-only parallel ToF UART capture. Never writes commands to the port.

Wire adapter RXD to ToF TXD and GND to GND only. Leave adapter TXD/VCC open.
Keep the existing sensor supply and FPGA input connected.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import re
import time

import serial
from serial.tools import list_ports


def classify(line):
    try:
        text = line.decode('ascii')
    except UnicodeDecodeError:
        return 'non_ascii', None
    match = re.match(r'^[ \t]*(\d+)(?:[^0-9].*)?$', text)
    if not match:
        return 'malformed', None
    number = int(match[1])
    if number == 0:
        return 'zero_distance', number
    if not 40 <= number <= 8000:
        return 'out_of_range', number
    return 'accepted_distance', number


def capture(port, seconds, label, root):
    devices = {p.device.upper(): p for p in list_ports.comports()}
    device = devices.get(port.upper())
    if device is None or 'BTHENUM' in device.hwid.upper():
        raise ValueError('Select the newly connected USB-TTL port, never the Bluetooth control port.')
    if not 1 <= seconds <= 120:
        raise ValueError('Capture duration must be 1..120 seconds.')
    stamp = dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    prefix = root / f'tof_raw_{label}_{stamp}'
    root.mkdir(parents=True, exist_ok=True)
    # No attached TXD/VCC; do not assert modem-control outputs either.
    connection = serial.Serial(port=None, baudrate=115200, timeout=0.05)
    connection.dtr = False
    connection.rts = False
    connection.port = port
    connection.open()
    start = time.monotonic()
    line_buffer = bytearray()
    counters = {}
    accepted_times = []
    byte_times = []
    records = []
    read_error = None
    try:
        with prefix.with_suffix('.bin').open('wb') as raw, prefix.with_suffix('.jsonl').open('w', encoding='utf-8') as log:
            while time.monotonic() - start < seconds:
                try:
                    data = connection.read(max(1, connection.in_waiting))
                except (serial.SerialException, OSError) as error:
                    read_error = repr(error)
                    break
                if not data:
                    continue
                elapsed = time.monotonic() - start
                byte_times.append(elapsed)
                raw.write(data)
                log.write(json.dumps(dict(seconds=elapsed, hex=data.hex())) + '\n')
                for byte in data:
                    if byte in (10, 13):
                        if not line_buffer:
                            continue
                        row = bytes(line_buffer)
                        line_buffer.clear()
                        kind, distance = classify(row)
                        counters[kind] = counters.get(kind, 0) + 1
                        records.append(dict(seconds=elapsed, kind=kind, distance_mm=distance,
                                            ascii=row.decode('ascii', errors='backslashreplace'), hex=row.hex()))
                        if kind == 'accepted_distance':
                            accepted_times.append(elapsed)
                    elif len(line_buffer) < 512:
                        line_buffer.append(byte)
                    else:
                        counters['overlong_unterminated'] = counters.get('overlong_unterminated', 0) + 1
                        line_buffer.clear()
    finally:
        connection.close()
    def intervals(points):
        gaps = [b - a for a, b in zip(points, points[1:])]
        return dict(count=len(points), maximum_gap_seconds=max(gaps) if gaps else None,
                    gaps_over_250ms=sum(g > 0.250 for g in gaps))
    duration = time.monotonic() - start
    valid_boundaries = [0.0, *accepted_times, duration]
    longest_without_valid = max(b-a for a,b in zip(valid_boundaries, valid_boundaries[1:]))
    summary = dict(port=port, label=label, baudrate=115200, duration_seconds=duration,
                   capture_complete=read_error is None, read_error=read_error,
                   serial_writes=0, counters=counters, valid_frames=intervals(accepted_times),
                   longest_without_accepted_frame_seconds=longest_without_valid,
                   receive_chunks=intervals(byte_times), unterminated_tail_hex=line_buffer.hex(),
                   raw_file=str(prefix.with_suffix('.bin')), rows=records,
                   note='Host normal-ASCII classifier and USB timestamps; raw retained. Not UART hardware framing-error flags or an exact model of R7 prefix/overflow handling.')
    prefix.with_suffix('.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in summary.items() if k != 'rows'}, ensure_ascii=True, indent=2), flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', required=True)
    parser.add_argument('--seconds', type=int, default=30)
    parser.add_argument('--label', required=True, choices=['near_1m', 'far_same_target', 'idle'])
    args = parser.parse_args()
    capture(args.port, args.seconds, args.label, Path(__file__).resolve().parents[1] / 'output/board/tof_raw')


if __name__ == '__main__':
    main()
