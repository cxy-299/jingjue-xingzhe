import argparse
from pathlib import Path
import cv2

from src.config import load_config
from src.camera.factory import create_camera


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config/config-pi.yaml")
    ap.add_argument("--output", default="logs/pi_camera_test.jpg")
    args = ap.parse_args()

    cfg = load_config(args.config)
    cam = create_camera(cfg["camera"])
    cam.open()

    try:
        ok, frame = cam.read()
        if not ok:
            raise RuntimeError("camera read failed")

        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(out), frame)

        print("[OK] Picamera2 frame captured")
        print(f"[OK] shape={frame.shape}")
        print(f"[OK] saved={out}")
    finally:
        cam.close()


if __name__ == "__main__":
    main()
