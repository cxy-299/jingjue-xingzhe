import cv2
from .base import CameraBase

class OpenCVCamera(CameraBase):
    def __init__(self, source=0, width=1280, height=720, fps=30,
                 flip_horizontal=False, flip_vertical=False):
        self.source, self.width, self.height, self.fps = source, int(width), int(height), int(fps)
        self.flip_horizontal, self.flip_vertical = bool(flip_horizontal), bool(flip_vertical)
        self.cap = None

    def open(self):
        source = int(self.source) if isinstance(self.source, str) and self.source.isdigit() else self.source
        self.cap = cv2.VideoCapture(source)
        if not self.cap.isOpened():
            raise RuntimeError(f'Cannot open camera/video source: {self.source}')
        if isinstance(source, int):
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
            self.cap.set(cv2.CAP_PROP_FPS, self.fps)

    def read(self):
        ok, frame = self.cap.read()
        if not ok: return False, None
        if self.flip_horizontal: frame = cv2.flip(frame, 1)
        if self.flip_vertical: frame = cv2.flip(frame, 0)
        return True, frame

    def close(self):
        if self.cap is not None:
            self.cap.release(); self.cap = None
