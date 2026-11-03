import argparse
import time
import cv2

from src.config import load_config
from src.camera.factory import create_camera
from src.detection.factory import create_detector
from src.detection.target_selector import TargetSelector
from src.comm.transport import TransportHub
from src.comm.protocol import pack_heartbeat, pack_vision_result
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentController


def draw_det(frame, d, selected=False):
    x1, y1, x2, y2 = map(int, [d.x1, d.y1, d.x2, d.y2])
    cv2.rectangle(
        frame, (x1, y1), (x2, y2),
        (255, 255, 255), 3 if selected else 1
    )
    cv2.putText(
        frame,
        f"{d.class_name} {d.confidence:.2f}",
        (x1, max(20, y1 - 8)),
        cv2.FONT_HERSHEY_SIMPLEX,
        .6,
        (255, 255, 255),
        2,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config/config-pi.yaml")
    args = ap.parse_args()

    cfg = load_config(args.config)

    cam = create_camera(cfg["camera"])
    det = create_detector(cfg)

    sel = TargetSelector(
        cfg["target"].get("class_names", []),
        cfg["target"].get("selection", "largest"),
        cfg["target"].get("min_area_ratio", 0),
        cfg["target"].get("red_bottle", {}),
    )

    vcfg = cfg.get("visual_alignment", {})
    aligner = VisualAlignmentController(
        center_target=vcfg.get("center_target", 5000),
        center_deadband=vcfg.get("center_deadband", .08),
        max_vy=vcfg.get("max_vy", .22),
        lateral_gain=vcfg.get("lateral_gain", 1.15),
        smoothing_alpha=vcfg.get("smoothing_alpha", .35),
        search_omega=vcfg.get("search_omega", .20),
        target_confirm_frames=vcfg.get("target_confirm_frames", 2),
        lost_confirm_frames=vcfg.get("lost_confirm_frames", 2),
    )

    links = TransportHub(cfg)

    display_enabled = bool(cfg.get("display", {}).get("enabled", False))
    print_interval = float(cfg.get("runtime", {}).get("print_interval_s", 0.5))

    hb_int = cfg.get("serial", {}).get("heartbeat_interval_ms", 500)
    seq = 0
    frame_id = 0
    start = int(time.monotonic() * 1000)
    last_hb = 0
    last_print = 0.0
    last_state = None
    prev = time.perf_counter()

    cam.open()
    links.open()

    print("[SYSTEM] LingShu Vision started")
    serial_status = links.status()["serial"]
    print(
        "[LINK] FPGA UART: "
        f"{'CONNECTED' if serial_status['connected'] else 'WAITING'} "
        f"{serial_status['port']}@{serial_status['baudrate']}"
    )
    print("[CONTROL] Pi sends perception only; FPGA owns all motion control")

    try:
        while True:
            ok, frame = cam.read()
            if not ok:
                print("[ERROR] Camera read failed")
                break

            now_ms = int(time.monotonic() * 1000)
            detections = det.detect(frame)
            target = sel.choose(detections, frame)
            obs = TargetObservation.from_detection(now_ms, target)
            alignment = aligner.update(obs)

            if links.enabled:
                links.send(
                    pack_vision_result(seq, obs, alignment, frame_id)
                )
                seq = (seq + 1) & 0xFFFF

                if now_ms - last_hb >= hb_int:
                    links.send(pack_heartbeat(seq, now_ms - start))
                    seq = (seq + 1) & 0xFFFF
                    last_hb = now_ms

            frame_id = (frame_id + 1) & 0xFFFFFFFF

            now = time.monotonic()
            if (
                alignment.state != last_state
                or now - last_print >= print_interval
            ):
                print(
                    f"[VISION] state={alignment.state:11s} "
                    f"valid={obs.valid} "
                    f"cx={obs.cx:5d} "
                    f"ex={alignment.center_error:+.3f} "
                    f"vy={alignment.vy:+.3f}"
                )
                last_state = alignment.state
                last_print = now

            if not display_enabled:
                continue

            for d in detections:
                if (
                    cfg["display"].get("show_all_detections", True)
                    or d is target
                ):
                    draw_det(frame, d, d is target)

            h, w = frame.shape[:2]
            cv2.drawMarker(
                frame,
                (w // 2, h // 2),
                (255, 255, 255),
                cv2.MARKER_CROSS,
                30,
                1,
            )

            target_msg = (
                f"TARGET {target.class_name} cx={obs.cx}"
                if target else "TARGET: NONE"
            )
            cv2.putText(
                frame,
                target_msg,
                (20, 35),
                cv2.FONT_HERSHEY_SIMPLEX,
                .7,
                (255, 255, 255),
                2,
            )
            cv2.putText(
                frame,
                (
                    f"VISION: {alignment.state} "
                    f"vy={alignment.vy:+.3f} "
                    f"ex={alignment.center_error:+.2f}"
                ),
                (20, 72),
                cv2.FONT_HERSHEY_SIMPLEX,
                .65,
                (255, 255, 255),
                2,
            )

            if cfg["display"].get("show_fps", True):
                t = time.perf_counter()
                fps = 1.0 / max(1e-6, t - prev)
                prev = t
                cv2.putText(
                    frame,
                    f"FPS {fps:.1f}",
                    (20, 106),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    .58,
                    (255, 255, 255),
                    2,
                )

            cv2.imshow(
                cfg["display"].get("window_name", "LingShu Vision"),
                frame,
            )
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

    except KeyboardInterrupt:
        print("\n[SYSTEM] Ctrl+C received")
    finally:
        links.close()
        cam.close()
        if display_enabled:
            cv2.destroyAllWindows()
        print("[SYSTEM] LingShu Vision stopped")


if __name__ == "__main__":
    main()
