from .opencv_camera import OpenCVCamera
from .picamera2_camera import Picamera2Camera

def create_camera(cfg):
    backend = str(cfg.get('backend','opencv')).lower()
    common = dict(width=cfg.get('width',1280), height=cfg.get('height',720), fps=cfg.get('fps',30),
                  flip_horizontal=cfg.get('flip_horizontal',False), flip_vertical=cfg.get('flip_vertical',False))
    if backend == 'opencv': return OpenCVCamera(source=cfg.get('source',0), **common)
    if backend == 'picamera2':
        return Picamera2Camera(
            awb_mode=cfg.get('awb_mode', 'auto'),
            awb_lock_after_s=cfg.get('awb_lock_after_s', 0),
            colour_gains=cfg.get('colour_gains'),
            **common,
        )
    raise ValueError(f'Unsupported camera backend: {backend}')
