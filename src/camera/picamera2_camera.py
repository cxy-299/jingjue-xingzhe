from .base import CameraBase


AWB_MODE_NAMES = {
    "auto": "Auto",
    "incandescent": "Incandescent",
    "tungsten": "Tungsten",
    "fluorescent": "Fluorescent",
    "indoor": "Indoor",
    "daylight": "Daylight",
    "cloudy": "Cloudy",
    "custom": "Custom",
}


class Picamera2Camera(CameraBase):
    def __init__(
        self,
        width=1280,
        height=720,
        fps=30,
        flip_horizontal=False,
        flip_vertical=False,
        awb_mode="auto",
        awb_lock_after_s=0,
        colour_gains=None,
    ):
        self.width = int(width)
        self.height = int(height)
        self.fps = int(fps)
        self.flip_horizontal = bool(flip_horizontal)
        self.flip_vertical = bool(flip_vertical)
        self.awb_mode = str(awb_mode).strip().lower()
        self.awb_lock_after_s = max(0.0, float(awb_lock_after_s))
        self.colour_gains = colour_gains
        self.picam2 = None

    def open(self):
        try:
            from picamera2 import Picamera2
        except ImportError as e:
            raise RuntimeError(
                "Picamera2不可用。请先执行: "
                "sudo apt install -y python3-picamera2"
            ) from e

        from libcamera import controls

        self.picam2 = Picamera2()
        awb_name = AWB_MODE_NAMES.get(self.awb_mode)
        if awb_name is None:
            valid = ", ".join(AWB_MODE_NAMES)
            raise ValueError(
                f"不支持的白平衡模式: {self.awb_mode}; 可用值: {valid}"
            )

        camera_controls = {"FrameRate": self.fps}
        if "AwbMode" in self.picam2.camera_controls:
            camera_controls["AwbMode"] = getattr(
                controls.AwbModeEnum, awb_name
            )

        if self.colour_gains is not None:
            if len(self.colour_gains) != 2:
                raise ValueError("colour_gains 必须是 [红色增益, 蓝色增益]")
            camera_controls["AwbEnable"] = False
            camera_controls["ColourGains"] = tuple(
                float(value) for value in self.colour_gains
            )

        cfg = self.picam2.create_video_configuration(
            main={
                "size": (self.width, self.height),
                "format": "RGB888",
            },
            controls=camera_controls,
        )
        self.picam2.configure(cfg)
        self.picam2.start()

        # Camera Module 3 supports autofocus. If the connected camera does not
        # expose autofocus controls, simply continue without it.
        try:
            if "AfMode" in self.picam2.camera_controls:
                self.picam2.set_controls(
                    {"AfMode": controls.AfModeEnum.Continuous}
                )
                print("[CAMERA] Continuous autofocus enabled")
        except Exception as e:
            print(f"[CAMERA] Autofocus not enabled: {e}")

        if self.colour_gains is not None:
            print(
                "[CAMERA] Manual white balance enabled: "
                f"red={float(self.colour_gains[0]):.3f}, "
                f"blue={float(self.colour_gains[1]):.3f}"
            )
        elif self.awb_lock_after_s > 0:
            self._lock_white_balance_after_stabilizing()
        else:
            print(f"[CAMERA] White balance mode: {self.awb_mode}")

    def _lock_white_balance_after_stabilizing(self):
        import time

        if not {
            "AwbEnable",
            "ColourGains",
        }.issubset(self.picam2.camera_controls):
            print("[CAMERA] White balance lock is not supported")
            return

        print(
            "[CAMERA] Stabilizing white balance for "
            f"{self.awb_lock_after_s:.1f}s"
        )
        time.sleep(self.awb_lock_after_s)
        metadata = self.picam2.capture_metadata()
        gains = metadata.get("ColourGains")
        if not gains:
            print("[CAMERA] Colour gains unavailable; keeping AWB enabled")
            return

        gains = tuple(float(value) for value in gains)
        self.picam2.set_controls(
            {
                "AwbEnable": False,
                "ColourGains": gains,
            }
        )
        print(
            "[CAMERA] White balance locked: "
            f"red={gains[0]:.3f}, blue={gains[1]:.3f}"
        )

    def read(self):
        import cv2

        # Picamera2 的 RGB888 缓冲区在小端 ARM 内存中的字节顺序可直接供
        # OpenCV 当作 BGR 使用。再次执行 RGB->BGR 会把红、蓝通道互换。
        frame = self.picam2.capture_array()

        if self.flip_horizontal:
            frame = cv2.flip(frame, 1)
        if self.flip_vertical:
            frame = cv2.flip(frame, 0)

        return True, frame

    def close(self):
        if self.picam2 is not None:
            self.picam2.stop()
            self.picam2.close()
            self.picam2 = None
