"""Field-bottle dataset store. Human review only; predictions are not labels."""
import datetime
import hashlib
import json
import math
from pathlib import Path
import shutil

SPLITS = ('train', 'val', 'test')
SCENES = ('full_bottle', 'partial_near', 'transparent_reflection',
          'left_right_edge', 'multiple_bottles', 'negative_distractors')


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf8')
    temp.replace(path)


class DatasetStore:
    def __init__(self, root):
        self.root = Path(root).resolve()

    def items(self):
        out = []
        for manifest in sorted((self.root/'raw').glob('*/manifest.jsonl')):
            session = manifest.parent.name
            info = manifest.parent/'session.json'
            split = json.loads(info.read_text(encoding='utf8')).get('split') if info.exists() else None
            for line in manifest.read_text(encoding='utf8').splitlines():
                r = json.loads(line)
                name = r['image']
                if Path(name).name != name or not name.endswith('.jpg'):
                    raise ValueError('Unsafe manifest image name')
                key = session+'/'+name
                ann_path = self.root/'annotations'/session/(name+'.json')
                ann = json.loads(ann_path.read_text(encoding='utf8')) if ann_path.exists() else None
                out.append(dict(id=key, session=session, image=name, scene=r.get('scene'),
                                split=split, sha256=r['sha256'], annotation=ann))
        return out

    def get(self, key):
        for item in self.items():
            if item['id'] == key:
                return item
        raise ValueError('Unknown image')

    def image_path(self, item):
        path = self.root/'raw'/item['session']/item['image']
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Raw image hash changed')
        return path

    def save_annotation(self, key, boxes, negative=False):
        import cv2
        item = self.get(key)
        image = cv2.imread(str(self.image_path(item)))
        if image is None:
            raise ValueError('Cannot decode image')
        height, width = image.shape[:2]
        if not isinstance(boxes, list) or len(boxes) > 50:
            raise ValueError('Invalid box list')
        if not boxes and negative is not True:
            raise ValueError('Empty labels require explicit no-bottle confirmation')
        if boxes and negative:
            raise ValueError('A negative image cannot contain bottle boxes')
        clean = []
        for box in boxes:
            if not isinstance(box, list) or len(box) != 4:
                raise ValueError('Use [x1,y1,x2,y2]')
            x1,y1,x2,y2 = map(float,box)
            if not all(math.isfinite(v) for v in (x1,y1,x2,y2)) or not (
                    0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height
                    and x2-x1 >= 2 and y2-y1 >= 2):
                raise ValueError('Box is outside image or too small')
            clean.append([x1,y1,x2,y2])
        annotation = dict(reviewed=True, source='human', image_sha256=item['sha256'],
            width=width, height=height, boxes=clean, negative=bool(negative),
            reviewed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        atomic_json(self.root/'annotations'/item['session']/(item['image']+'.json'), annotation)
        return annotation

    def export(self, destination):
        """Session split is chosen before capture; never scatter adjacent frames."""
        reviewed = [i for i in self.items() if (i.get('annotation') or {}).get('reviewed')]
        counts = {s:dict(images=0, positives=0, negatives=0, sessions=set()) for s in SPLITS}
        hashes = {}
        for item in reviewed:
            split, ann = item['split'], item['annotation']
            if split not in SPLITS:
                raise ValueError('Reviewed session has no train/val/test assignment')
            self.image_path(item)
            if ann['image_sha256'] != item['sha256'] or ann.get('source') != 'human':
                raise ValueError('Annotation is not matched human review')
            old = hashes.setdefault(item['sha256'], split)
            if old != split:
                raise ValueError('Identical image leaks between splits')
            counts[split]['images'] += 1
            counts[split]['positives' if ann['boxes'] else 'negatives'] += 1
            counts[split]['sessions'].add(item['session'])
        warnings = []
        for split, minimum in (('train',60),('val',15),('test',15)):
            c = counts[split]
            if not c['images']:
                raise ValueError(f'{split}: 没有已审核图片，请为该组采集并标注至少一张')
            if c['images'] < minimum or len(c['sessions']) < 2:
                warnings.append(f'{split}: 当前{c["images"]}张/{len(c["sessions"])}段，'
                                f'建议至少{minimum}张、两个独立场景会话')
            if not c['positives']:
                warnings.append(f'{split}: 没有瓶子正样本，无法评估该组瓶子检出能力')
            if not c['negatives']:
                warnings.append(f'{split}: 没有经人工确认的无瓶子负样本，无法据此充分评价空场误检')
        destination = Path(destination).resolve()
        if destination.exists():
            raise ValueError('Export destination already exists; use a new release directory')
        destination.mkdir(parents=True)
        for item in reviewed:
            split, ann = item['split'], item['annotation']
            name = item['session']+'_'+item['image']
            images, labels = destination/'images'/split, destination/'labels'/split
            images.mkdir(parents=True,exist_ok=True); labels.mkdir(parents=True,exist_ok=True)
            shutil.copy2(self.image_path(item), images/name)
            lines = ['0 {:.8f} {:.8f} {:.8f} {:.8f}'.format(
                (x1+x2)/2/ann['width'], (y1+y2)/2/ann['height'],
                (x2-x1)/ann['width'], (y2-y1)/ann['height']) for x1,y1,x2,y2 in ann['boxes']]
            (labels/Path(name).with_suffix('.txt')).write_text('\n'.join(lines),encoding='utf8')
        import yaml
        (destination/'dataset.yaml').write_text(yaml.safe_dump(dict(path=destination.as_posix(),
            train='images/train',val='images/val',test='images/test',names={0:'bottle'})),encoding='utf8')
        report = dict(classes={0:'bottle'}, protocol_mapping_required={'bottle':39},
                      counts={s:{**v,'sessions':sorted(v['sessions'])} for s,v in counts.items()},
                      items=reviewed, candidate_only=True, quality_warnings=warnings,
                      unreviewed_images_excluded=len(self.items())-len(reviewed))
        atomic_json(destination/'review_manifest.json',report)
        return str(destination/'dataset.yaml')
