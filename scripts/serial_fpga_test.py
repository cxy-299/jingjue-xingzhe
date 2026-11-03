import argparse
import time

from src.comm.protocol import pack_heartbeat, pack_vision_result
from src.comm.serial_link import SerialLink
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentResult


def main():
    parser = argparse.ArgumentParser(
        description="Send deterministic test vision frames to FPGA over UART"
    )
    parser.add_argument("--port", default="auto_usb_ch340")
    parser.add_argument("--baudrate", type=int, default=115200)
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument("--interval", type=float, default=0.25)
    parser.add_argument("--no-target-seconds", type=float, default=2.0)
    parser.add_argument("--timeout-seconds", type=float, default=2.0)
    args = parser.parse_args()

    link = SerialLink(
        enabled=True,
        port=args.port,
        baudrate=args.baudrate,
        reconnect_interval_s=0.5,
    )
    if not link.open():
        raise SystemExit(f"Cannot open UART: {link.last_error}")

    print(f"UART test started: {args.port}@{args.baudrate}")
    try:
        for index in range(max(1, args.count)):
            is_left = index % 2 == 0
            observation = TargetObservation(
                timestamp_ms=int(time.monotonic() * 1000),
                valid=True,
                class_id=39,
                class_name="bottle",
                confidence=0.90,
                cx=3000 if is_left else 7000,
                cy=5000,
                w=1800,
                h=3600,
            )
            alignment = VisualAlignmentResult(
                state="ALIGN_LEFT" if is_left else "ALIGN_RIGHT",
                vy=0.0,
                omega=0.0,
                center_error=-0.4 if is_left else 0.4,
                reason="UART test",
            )
            frame = pack_vision_result(
                index * 2, observation, alignment, index
            )
            heartbeat = pack_heartbeat(index * 2 + 1, index * 1000)
            if not link.send(frame) or not link.send(heartbeat):
                raise SystemExit(f"UART write failed: {link.last_error}")
            print(
                f"#{index:02d} {'LEFT ' if is_left else 'RIGHT'} "
                f"vision={frame.hex(' ')}"
            )
            time.sleep(max(0.01, args.interval))

        # 第二阶段持续发“无目标”视觉帧：链路和视觉仍新鲜，但目标灯必须熄灭。
        no_target_until = time.monotonic() + max(0.0, args.no_target_seconds)
        next_seq = max(1, args.count) * 2
        no_target_frame_id = max(1, args.count)
        print("[STAGE 2] 无目标：LED3/4 应亮，LED5/6 应灭，LED7 应灭")
        while time.monotonic() < no_target_until:
            observation = TargetObservation(
                timestamp_ms=int(time.monotonic() * 1000), valid=False
            )
            alignment = VisualAlignmentResult(
                state="SEARCH", vy=0.0, omega=0.0,
                center_error=0.0, reason="UART no-target test",
            )
            if not link.send(pack_vision_result(
                    next_seq, observation, alignment, no_target_frame_id)):
                raise SystemExit(f"UART write failed: {link.last_error}")
            next_seq += 1
            no_target_frame_id += 1
            time.sleep(max(0.01, args.interval))

        # 第三阶段不再发送：超过 FPGA 的 1.5 s 看门狗后链路/视觉灯均应熄灭。
        print("[STAGE 3] 停止发送：约 1.5 秒后 LED3–LED6 应全部熄灭")
        time.sleep(max(0.0, args.timeout_seconds))
    finally:
        link.close()

    print("UART test completed")


if __name__ == "__main__":
    main()
