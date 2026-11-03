"""Train a candidate only from a manually reviewed dataset release.

Default is preflight; --run starts training, never deploys a model or sends UART.
Use isolated Ultralytics 8.3.0 to match the Pi's YOLO11 architecture code.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path

import yaml


def check_dataset(data):
    data=Path(data).resolve()
    cfg=yaml.safe_load(data.read_text(encoding='utf8'))
    if cfg.get('names') != {0:'bottle'}:
        raise ValueError('Expected reviewed single-class bottle dataset')
    root=Path(cfg['path']).resolve()
    if root != data.parent:
        raise ValueError('Dataset release path does not match YAML')
    report=json.loads((root/'review_manifest.json').read_text(encoding='utf8'))
    for split,minimum in (('train',60),('val',15),('test',15)):
        info=report['counts'][split]
        if info['images'] < minimum or not info['positives'] or len(info['sessions'])<2:
            raise ValueError(f'{split}: review coverage is insufficient')
    hashes={}
    counts={s:0 for s in ('train','val','test')}
    for item in report['items']:
        split=item['split']; ann=item['annotation']
        name=item['session']+'_'+item['image']
        image=root/'images'/split/name
        digest=hashlib.sha256(image.read_bytes()).hexdigest()
        if digest != item['sha256'] or digest != ann['image_sha256'] or ann.get('source') != 'human':
            raise ValueError('Dataset content/review hash changed')
        if hashes.setdefault(digest,split) != split:
            raise ValueError('Image leaks across train/val/test')
        expected=['0 {:.8f} {:.8f} {:.8f} {:.8f}'.format(
            (x1+x2)/2/ann['width'],(y1+y2)/2/ann['height'],
            (x2-x1)/ann['width'],(y2-y1)/ann['height']) for x1,y1,x2,y2 in ann['boxes']]
        actual=(root/'labels'/split/Path(name).with_suffix('.txt')).read_text(encoding='utf8').splitlines()
        if actual != expected:
            raise ValueError('Exported labels differ from human review')
        counts[split]+=1
    if any(counts[s] != report['counts'][s]['images'] for s in counts):
        raise ValueError('Dataset review count is inconsistent')
    # Explicit directory paths mean added unreviewed images would also be read
    # by YOLO. Require exactly the reviewed list before training.
    if sum(len(list((root/'images'/s).glob('*'))) for s in counts) != len(report['items']):
        raise ValueError('Unexpected image added after review export')
    return dict(data=str(data),counts=counts,
        quality_warnings=report.get('quality_warnings', []),
        review_sha256=hashlib.sha256((root/'review_manifest.json').read_bytes()).hexdigest(),
        native_class_id=0,fpga_bottle_class_id=39,deployment_allowed=False)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--data',required=True,type=Path)
    p.add_argument('--base',type=Path,default=Path('models/training_base/yolo11n.pt'))
    p.add_argument('--device',default='0')
    p.add_argument('--epochs',type=int,default=80)
    p.add_argument('--run',action='store_true')
    a=p.parse_args()
    report=check_dataset(a.data)
    print(json.dumps(report,ensure_ascii=False,indent=2))
    if not a.run: return
    if not 1 <= a.epochs <= 300: p.error('epochs must be 1..300')
    if not a.base.is_file(): p.error('Missing trusted local base weights; no automatic download')
    import ultralytics
    if ultralytics.__version__ != '8.3.0':
        p.error('Use isolated training environment with ultralytics==8.3.0 (matches Pi)')
    import torch
    if a.device != 'cpu' and not torch.cuda.is_available():
        p.error('CUDA unavailable in this interpreter; see setup guide or explicitly use --device cpu')
    # Old YOLO checkpoints include Python model classes. Limit this compatibility
    # setting to the training process and locally verified base/candidate files.
    os.environ['TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD']='1'
    from ultralytics import YOLO
    name=datetime.datetime.now(datetime.timezone.utc).strftime('bottle_%Y%m%dT%H%M%SZ')
    project=Path('output/training').resolve()
    report.update(base_sha256=hashlib.sha256(a.base.read_bytes()).hexdigest(),
                  ultralytics=ultralytics.__version__,torch=torch.__version__,device=a.device)
    run_dir=project/name
    if run_dir.exists():p.error('Run directory already exists')
    run_dir.mkdir(parents=True)
    # Save input evidence BEFORE the long run, including failures/interruptions.
    report.update(requested_epochs=a.epochs,imgsz=416,batch=8,
                  source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (run_dir/'input_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    model=YOLO(str(a.base))
    # Match 416 Pi input; moderate crop/scale, no mosaic mixing partial bottle
    # fragments into artificial positives. These are initial settings, not an
    # assertion of optimal accuracy. Test set is NOT used during training.
    model.train(data=report['data'],epochs=a.epochs,imgsz=416,batch=8,
        device=a.device,workers=0,project=str(project),name=name,exist_ok=True,
        patience=20,seed=2613,deterministic=True,mosaic=0.0,mixup=0.0,
        degrees=5.0,translate=.1,scale=.25,fliplr=.5,flipud=0.0,amp=False)
    best=Path(model.trainer.best)
    report.update(candidate=str(best),candidate_sha256=hashlib.sha256(best.read_bytes()).hexdigest(),
                  test_used=False,pi_latency_verified=False,pi_load_verified=False)
    (best.parent.parent/'candidate_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('Candidate saved. Requires held-out comparison, Pi compatibility, 0->39 class mapping and latency checks. Not deployed.')


if __name__=='__main__': main()
