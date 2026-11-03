"""Explicit backend; A4 mode does not run or load YOLO."""
def create_detector(cfg):
    backend=cfg.get('perception',{}).get('backend','yolo')
    if backend=='a4_digits':
        from src.detection.printed_digit import PrintedDigitDetector
        return PrintedDigitDetector(cfg.get('perception',{}).get('a4_digits',{}))
    if backend!='yolo': raise ValueError('Unknown perception backend: '+str(backend))
    from src.detection.yolo_detector import YOLODetector
    model=cfg['model']
    return YOLODetector(model['path'],model.get('conf_threshold',.45),model.get('iou_threshold',.5),
                        model.get('imgsz',416),model.get('device','cpu'),near_bottle=model.get('near_bottle',{}))

