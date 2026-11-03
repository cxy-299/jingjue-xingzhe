"""Reproducible valid/bad-CRC/obsolete-map UART vectors for SIN12 integration."""
from pathlib import Path
from src.comm.autonav import pack_autonav_goal
from src.comm.protocol import build_frame, parse_frame


def main():
    good = pack_autonav_goal(41, (17, 2), (17, 3), 1000, 0, True, False, 12)
    bad = good[:-1] + bytes([good[-1] ^ 1])
    payload = bytearray(parse_frame(good)['payload'])
    payload[:2] = bytes.fromhex('12 26')
    obsolete = build_frame(0x26, 42, bytes(payload))
    dest = Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive/sin12_packet_frames.mem'
    dest.write_text(''.join(f'{b:02x}\n' for frame in (good, bad, obsolete) for b in frame), encoding='ascii')
    print('SIN12 fixtures: valid new map, bad CRC, valid CRC obsolete map')


if __name__ == '__main__':
    main()
