import cv2
from src.config import load_config
from src.camera.factory import create_camera
cfg=load_config('config/config.yaml'); cam=create_camera(cfg['camera']); cam.open()
try:
    while True:
        ok,frame=cam.read()
        if not ok: break
        cv2.imshow('Camera Test',frame)
        if cv2.waitKey(1)&0xFF==ord('q'): break
finally:
    cam.close(); cv2.destroyAllWindows()
