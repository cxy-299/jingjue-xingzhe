"""Bridge FPGA motor telemetry to VOFA+ JustFloat over UDP.

The FPGA Bluetooth link is exclusive on Windows, so close the unified console
before running this bridge.  It is intentionally read-only: it never writes a
motion command or PID parameter to the robot.

Channels (16 floats): M1..M4 target count, measured count, duty permille,
fault flag.  VOFA+ JustFloat uses a little-endian float payload followed by
the 0x0000807f frame tail.
"""

from __future__ import annotations

import argparse
import csv
import re
import socket
import struct
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


MOTOR_RE = re.compile(
    r"^M([1-4])\s+T([+-]?\d+)\s+A([+-]?\d+)\s+D(\d+)\s+F([01])$"
)
CHANNELS = tuple(f"M{motor}_{name}" for motor in range(1, 5) for name in ("T", "A", "D", "F"))


@dataclass
class MotorState:
    target: float = 0.0
    actual: float = 0.0
    duty: float = 0.0
    fault: float = 0.0


@dataclass
class Telemetry:
    motors: dict[int, MotorState] = field(default_factory=lambda: {i: MotorState() for i in range(1, 5)})

    def update_line(self, line: str) -> bool:
        match = MOTOR_RE.fullmatch(line.strip())
        if match is None:
            return False
        motor, target, actual, duty, fault = match.groups()
        state = self.motors[int(motor)]
        state.target = float(int(target))
        state.actual = float(int(actual))
        state.duty = float(int(duty))
        state.fault = float(int(fault))
        return True

    def values(self) -> list[float]:
        result: list[float] = []
        for motor in range(1, 5):
            state = self.motors[motor]
            result.extend((state.target, state.actual, state.duty, state.fault))
        return result


def justfloat_packet(values: list[float]) -> bytes:
    return struct.pack("<" + "f" * len(values), *values) + struct.pack("<I", 0x0000807F)


def _csv_writer(path: str | None):
    if not path:
        return None, None
    handle = Path(path).open("w", newline="", encoding="utf-8")
    writer = csv.writer(handle)
    writer.writerow(("timestamp", *CHANNELS))
    return handle, writer


def run(port: str, baud: int, udp_host: str, udp_port: int, csv_path: str | None) -> None:
    try:
        import serial
    except ImportError as exc:  # pragma: no cover - environment diagnostic
        raise SystemExit("缺少 pyserial：python -m pip install pyserial") from exc

    serial_port = serial.Serial(port, baudrate=baud, timeout=0.2)
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    telemetry = Telemetry()
    csv_handle, csv_writer = _csv_writer(csv_path)
    print(f"读取 {port} {baud} 8N1，JustFloat UDP {udp_host}:{udp_port}；只读，不发送电机命令", flush=True)
    try:
        while True:
            raw = serial_port.readline()
            if not raw:
                continue
            line = raw.decode("ascii", "replace").strip()
            if not telemetry.update_line(line):
                continue
            values = telemetry.values()
            udp.sendto(justfloat_packet(values), (udp_host, udp_port))
            if csv_writer is not None:
                csv_writer.writerow((f"{time.time():.3f}", *values))
                csv_handle.flush()
            print(line, flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        serial_port.close()
        udp.close()
        if csv_handle is not None:
            csv_handle.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="FPGA M1..M4 telemetry to VOFA+ JustFloat")
    parser.add_argument("--port", default="COM9")
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--udp-host", default="127.0.0.1")
    parser.add_argument("--udp-port", type=int, default=1347)
    parser.add_argument("--csv", help="同时保存 CSV 遥测记录")
    args = parser.parse_args(argv)
    run(args.port, args.baud, args.udp_host, args.udp_port, args.csv)
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
