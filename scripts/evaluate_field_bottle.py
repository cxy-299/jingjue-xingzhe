"""Compare bottle detection at the deployed operating threshold on reviewed data.

All detections are matched by class NAME, so native candidate ID0 is never
mistaken for COCO person ID0. This is offline evaluation, not a UART adapter.
Reports fixed-threshold precision/recall, NOT COCO mAP or Pi runtime latency.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import time

from scripts.train_field_bottle import check_dataset


def iou(a,b):
    intersection=max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
    return intersection/max(1e-9,(a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-intersection)


def score_frame(predictions, truth, width, threshold=.5):
    """Confidence-ordered one-to-one matching, no duplicate TP for one object."""
    remaining=set(range(len(truth)))
    tp=0; center_errors=[]
    for prediction in sorted(predictions,key=lambda p:p['confidence'],reverse=True):
        if not remaining: break
        candidate=max(remaining,key=lambda i:iou(prediction['box'],truth[i]))
        if iou(prediction['box'],truth[candidate]) < threshold: continue
        tp+=1; remaining.remove(candidate)
        p,g=prediction['box'],truth[candidate]
        center_errors.append(abs((p[0]+p[2]-g[0]-g[2])/2)/width)
    return dict(tp=tp,fp=len(predictions)-tp,fn=len(truth)-tp,
                center_abs_error_fraction=center_errors)


def summarize(rows):
    tp=sum(r['tp'] for r in rows);fp=sum(r['fp'] for r in rows);fn=sum(r['fn'] for r in rows)
    negatives=[r for r in rows if not r['truth']]
    errors=[v for r in rows for v in r['center_abs_error_fraction']]
    return dict(images=len(rows),tp=tp,fp=fp,fn=fn,
        precision=tp/(tp+fp) if tp+fp else None, recall=tp/(tp+fn) if tp+fn else None,
        negative_images=len(negatives),negative_images_with_false_positive=sum(bool(r['fp']) for r in negatives),
        positive_frames_without_any_bottle=sum(bool(r['truth']) and not r['predictions'] for r in rows),
        center_abs_error_fraction_median=statistics.median(errors) if errors else None,
        host_median_inference_ms=statistics.median([r['inference_ms'] for r in rows]) if rows else None)


def evaluate(model_path, manifest, root, split, mode, device):
    import cv2
    import torch
    from src.detection.yolo_detector import YOLODetector
    detector=YOLODetector(str(model_path),.45,.5,416,device,
                          near_bottle={'enabled':mode=='production'})
    names=detector.model.names
    if 'bottle' not in names.values(): raise ValueError('Model does not support bottle')
    selected=sorted([i for i in manifest['items'] if i['split']==split],key=lambda i:(i['session'],i['image']))
    first=cv2.imread(str(root/'images'/split/(selected[0]['session']+'_'+selected[0]['image'])))
    detector.detect(first,target_class='bottle')  # warmup, excluded from metrics
    rows=[]; session=None
    for i,item in enumerate(selected):
        name=item['session']+'_'+item['image']
        frame=cv2.imread(str(root/'images'/split/name))
        if frame is None:raise ValueError('Image decode failed: '+name)
        if item['session']!=session:
            detector._near_remaining=detector._frame_number=detector._misses=0
            session=item['session']
        if device!='cpu': torch.cuda.synchronize()
        started=time.perf_counter()
        detections=detector.detect(frame,target_class='bottle')
        if device!='cpu': torch.cuda.synchronize()
        elapsed=(time.perf_counter()-started)*1000
        predictions=[dict(box=[d.x1,d.y1,d.x2,d.y2],confidence=d.confidence,native_class_id=d.class_id,
                          source=d.source) for d in detections if d.class_name=='bottle']
        truth=item['annotation']['boxes']
        partial=any(b[0]<=2 or b[1]<=2 or b[2]>=frame.shape[1]-2 or b[3]>=frame.shape[0]-2 for b in truth)
        rows.append(dict(image=name,session=session,scene=item['scene'],truth=truth,predictions=predictions,
            inference_ms=elapsed,partial=partial,detector_passes=detector.status['detector_passes'],
            **score_frame(predictions,truth,frame.shape[1])))
        if (i+1)%25==0:print(f'{Path(model_path).name} {mode}: {i+1}/{len(selected)}',flush=True)
    return dict(model=str(Path(model_path).resolve()),sha256=hashlib.sha256(Path(model_path).read_bytes()).hexdigest(),
        native_names=names,mode=mode,summary=summarize(rows),partial_summary=summarize([r for r in rows if r['partial']]),
        rows=rows)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--data',type=Path,required=True)
    p.add_argument('--base',type=Path,default=Path('models/training_base/yolo11n.pt'))
    p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--split',choices=('val','test'),default='val')
    p.add_argument('--device',default='0')
    p.add_argument('--out',type=Path,required=True)
    a=p.parse_args()
    if a.out.exists(): p.error('Do not overwrite evaluation evidence; use a new file')
    preflight=check_dataset(a.data)
    os.environ['TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD']='1'
    root=a.data.resolve().parent
    manifest=json.loads((root/'review_manifest.json').read_text(encoding='utf8'))
    results=[]
    for model in (a.base,a.candidate):
        for mode in ('raw','production'):
            results.append(evaluate(model,manifest,root,a.split,mode,a.device))
    report=dict(dataset=preflight,split=a.split,conf=.45,nms_iou=.5,matching_iou=.5,imgsz=416,
        device=a.device,latency_scope='This host only; not a Pi throughput or motion test',
        metric_scope='Fixed operating threshold, class-name bottle, confidence-ordered one-to-one IoU matching; not mAP',
        deployed=False,results=results)
    a.out.parent.mkdir(parents=True,exist_ok=True)
    a.out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps([dict(model=r['model'],mode=r['mode'],**r['summary']) for r in results],indent=2),flush=True)


if __name__=='__main__':main()
