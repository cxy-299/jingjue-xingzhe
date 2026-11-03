import cv2
from src.config import load_config
from src.detection.yolo_detector import YOLODetector
cfg=load_config('config/config.yaml'); m=cfg['model']; d=YOLODetector(m['path'],m.get('conf_threshold',.45),m.get('iou_threshold',.5),m.get('imgsz',640),m.get('device','cpu'))
cap=cv2.VideoCapture(cfg['camera'].get('source',0))
while True:
    ok,frame=cap.read()
    if not ok: break
    for x in d.detect(frame):
        cv2.rectangle(frame,(int(x.x1),int(x.y1)),(int(x.x2),int(x.y2)),(255,255,255),2)
        cv2.putText(frame,f'{x.class_name} {x.confidence:.2f}',(int(x.x1),max(20,int(x.y1)-8)),cv2.FONT_HERSHEY_SIMPLEX,.6,(255,255,255),2)
    cv2.imshow('Detector Test',frame)
    if cv2.waitKey(1)&0xFF==ord('q'): break
cap.release(); cv2.destroyAllWindows()
