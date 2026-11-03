import argparse
import time

import serial
from serial.tools import list_ports

from src.comm.protocol import (
    MSG_HEARTBEAT,
    MSG_VISION_RESULT,
    unpack_heartbeat_payload,
    unpack_vision_result_payload,
)
from src.comm.stream_parser import FrameStreamParser


def available_ports():
    return list(list_ports.comports())


def main():
    parser = argparse.ArgumentParser(
        description="Windows serial assistant for Raspberry Pi YOLO frames"
    )
    parser.add_argument("--port", help="USB-TTL port, for example COM5")
    parser.add_argument("--baudrate", type=int, default=115200)
    args = parser.parse_args()

    ports = available_ports()
    if not args.port:
        if not ports:
            raise SystemExit(
                "No COM port detected. Plug in the USB-TTL adapter first."
            )
        print("Available COM ports:")
        for port in ports:
            print(f"  {port.device}: {port.description}")
        raise SystemExit("Run again with --port COMx")

    decoder = FrameStreamParser()
    heartbeat_printed = 0.0
    frame_count = 0
    with serial.Serial(args.port, args.baudrate, timeout=0.2) as link:
        print(f"Listening on {args.port}@{args.baudrate}, 8-N-1")
        print("Press Ctrl+C to stop.")
        try:
            while True:
                chunk = link.read(max(1, link.in_waiting))
                for frame in decoder.feed(chunk):
                    if frame["msg_type"] == MSG_VISION_RESULT:
                        result = unpack_vision_result_payload(frame["payload"])
                        frame_count += 1
                        print(
                            f"[VISION #{frame_count}] seq={frame['seq']} "
                            f"valid={int(result['valid'])} "
                            f"confirmed={int(result['confirmed'])} "
                            f"class={result['class_id']} "
                            f"conf={result['confidence']:.3f} "
                            f"cx={result['cx']} "
                            f"error={result['center_error']:+.3f} "
                            f"area={result['area_ratio']:.4f} "
                            f"state={result['alignment']}"
                        )
                    elif frame["msg_type"] == MSG_HEARTBEAT:
                        now = time.monotonic()
                        if now - heartbeat_printed >= 2.0:
                            heartbeat = unpack_heartbeat_payload(
                                frame["payload"]
                            )
                            print(
                                f"[HEARTBEAT] seq={frame['seq']} "
                                f"uptime_ms={heartbeat['uptime_ms']}"
                            )
                            heartbeat_printed = now
        except KeyboardInterrupt:
            pass

    print(
        f"Stopped. Valid vision frames={frame_count}, "
        f"bad frames={decoder.bad_frames}"
    )


if __name__ == "__main__":
    main()
