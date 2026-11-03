import argparse
import socket
import time
import os

from src.comm.protocol import (
    MSG_HEARTBEAT,
    MSG_VISUAL_ALIGNMENT,
    MSG_VISION_RESULT,
    parse_frame,
    unpack_heartbeat_payload,
    unpack_visual_alignment_payload,
    unpack_vision_result_payload,
)
from src.core.mock_tof import MockToF
from src.core.tof_control import ToFDistanceController


def read_key_nonblocking():
    if os.name != 'nt':
        return None
    import msvcrt
    if msvcrt.kbhit():
        return msvcrt.getwch().lower()
    return None


def classify_final(vx, vy, alignment, tof_state):
    if tof_state in ('TOF_FAULT', 'HARD_STOP'):
        return tof_state
    if alignment == 'SEARCH':
        return 'SEARCH'
    if abs(vx) < 0.005 and abs(vy) < 0.005:
        return 'STOP'
    if vx > 0.005 and vy < -0.005:
        return 'APPROACH_LEFT'
    if vx > 0.005 and vy > 0.005:
        return 'APPROACH_RIGHT'
    if vx > 0.005:
        return 'APPROACH'
    if vy < -0.005:
        return 'ALIGN_LEFT'
    if vy > 0.005:
        return 'ALIGN_RIGHT'
    return 'HOLD'


def fpga_lateral_control(center_error, deadband=0.08, max_vy=0.22):
    """Reference behavior for FPGA logic; Pi sends no velocity command."""
    error = max(-1.0, min(1.0, float(center_error)))
    if abs(error) <= deadband:
        return 0.0
    normalized = (abs(error) - deadband) / (1.0 - deadband)
    return (1.0 if error > 0 else -1.0) * max_vy * normalized


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=9999)
    ap.add_argument('--config', default='config/config.yaml')
    args = ap.parse_args()

    from src.config import load_config
    cfg = load_config(args.config)

    tcfg = cfg.get('mock_tof', {})
    tof = MockToF(
        start_mm=tcfg.get('start_mm', 1500),
        step_mm=tcfg.get('step_mm', 100),
        min_mm=tcfg.get('min_mm', 100),
        max_mm=tcfg.get('max_mm', 3000),
    )

    dcfg = cfg.get('tof_distance_control', {})
    distance_ctrl = ToFDistanceController(
        target_mm=dcfg.get('target_mm', 500),
        deadband_mm=dcfg.get('deadband_mm', 50),
        hard_stop_mm=dcfg.get('hard_stop_mm', 250),
        max_vx=dcfg.get('max_vx', .28),
        min_vx=dcfg.get('min_vx', .04),
        kp=dcfg.get('kp', .00035),
        smoothing_alpha=dcfg.get('smoothing_alpha', .35),
    )

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.host, args.port))
    sock.settimeout(0.05)

    print('=' * 72)
    print(' 灵枢智行 - 模拟 FPGA：视觉左右对位 + ToF前后距离')
    print(f' UDP: {args.host}:{args.port}')
    print(' 键盘：S=模拟靠近(-距离)  W=模拟远离(+距离)')
    print('       I=ToF有效/失效切换  R=距离重置  Q=退出')
    print('=' * 72)

    last_packet_t = None
    last_visual = None
    last_print = 0.0
    last_action = None

    try:
        running = True
        while running:
            key = read_key_nonblocking()
            if key == 's':
                tof.closer()
            elif key == 'w':
                tof.farther()
            elif key == 'i':
                tof.toggle_valid()
            elif key == 'r':
                tof.reset(tcfg.get('start_mm', 1500))
                distance_ctrl.reset()
            elif key == 'q':
                running = False
                continue

            try:
                data, _ = sock.recvfrom(4096)
            except socket.timeout:
                data = None

            now = time.monotonic()

            if data:
                try:
                    frame = parse_frame(data)
                except ValueError as e:
                    print(f'[RX ERROR] {e}')
                    continue

                last_packet_t = now

                if frame['msg_type'] == MSG_VISUAL_ALIGNMENT:
                    last_visual = unpack_visual_alignment_payload(frame['payload'])

                elif frame['msg_type'] == MSG_VISION_RESULT:
                    last_visual = unpack_vision_result_payload(frame['payload'])

                elif frame['msg_type'] == MSG_HEARTBEAT:
                    _ = unpack_heartbeat_payload(frame['payload'])

            # Watchdog: no visual packet -> all motion zero.
            if last_packet_t is None or now - last_packet_t > 1.0:
                distance_ctrl.reset()
                if now - last_print > 1.0:
                    print('[WATCHDOG] vision timeout -> vx=0 vy=0 omega=0')
                    last_print = now
                continue

            if last_visual is None:
                continue

            visual_valid = last_visual['valid'] and last_visual.get(
                'confirmed', True
            )
            alignment = last_visual['alignment']

            # Conservative rule: no visual target => never approach forward.
            if not visual_valid:
                distance_ctrl.reset()
                vx = 0.0
                vy = 0.0
                omega = 0.20 if alignment == 'SEARCH' else 0.0
                tof_result = None
                action = 'SEARCH' if alignment == 'SEARCH' else 'HOLD'
            else:
                tof_result = distance_ctrl.update(tof.distance_mm, tof.valid)

                # ToF invalid/hard-stop => full stop, not merely vx stop.
                if tof_result.state in ('TOF_FAULT', 'HARD_STOP'):
                    vx = 0.0
                    vy = 0.0
                    omega = 0.0
                else:
                    vx = tof_result.vx
                    vy = fpga_lateral_control(last_visual['center_error'])
                    omega = 0.0

                action = classify_final(
                    vx, vy, alignment,
                    tof_result.state
                )

            # Print on action change or every 0.6 s.
            if action != last_action or now - last_print > 0.6:
                print()
                print(f'[FUSION] action={action}')
                print(
                    f"  Vision : {alignment:12s} "
                    f"cx={last_visual['cx']:5d} "
                    f"ex={last_visual['center_error']:+.2f} "
                    f"area={last_visual.get('area_ratio', 0.0):.3f}"
                )
                print(
                    f"  ToF    : {'VALID' if tof.valid else 'INVALID':7s} "
                    f"distance={tof.distance_mm:4d} mm"
                )
                if tof_result:
                    print(
                        f"  DistCtl: {tof_result.state:12s} "
                        f"error={tof_result.distance_error_mm:+5d} mm"
                    )
                print(f'  FPGA   : vx={vx:+.3f}  vy={vy:+.3f}  omega={omega:+.3f}')
                print('  Safety : watchdog + ToF fault + hard stop have priority')
                last_action = action
                last_print = now

    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
        print('\n模拟 FPGA 已退出。')


if __name__ == '__main__':
    main()
