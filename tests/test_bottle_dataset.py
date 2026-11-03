import hashlib
import json
from pathlib import Path
from http.server import ThreadingHTTPServer
import threading
import urllib.request
import urllib.error
import base64

import cv2
import numpy as np
import pytest

from scripts.bottle_dataset import DatasetStore, atomic_json
from scripts.bottle_dataset_gui import Collector, handler
from scripts.train_field_bottle import check_dataset
import scripts.capture_pi_training_frames as capture


def sample(store,session='a',number=0,split='train',seed=0):
    directory=store.root/'raw'/session; directory.mkdir(parents=True,exist_ok=True)
    image=np.random.default_rng(seed).integers(0,255,(48,64,3),dtype=np.uint8)
    ok,data=cv2.imencode('.jpg',image); assert ok
    name=f'{number:05d}.jpg'; (directory/name).write_bytes(data.tobytes())
    atomic_json(directory/'session.json',dict(split=split))
    with (directory/'manifest.jsonl').open('a',encoding='utf8') as f:
        f.write(json.dumps(dict(image=name,sha256=hashlib.sha256(data).hexdigest(),scene='test'))+'\n')
    return session+'/'+name


def test_manual_negative_is_explicit_and_raw_hash_is_verified(tmp_path):
    store=DatasetStore(tmp_path); key=sample(store)
    with pytest.raises(ValueError,match='explicit'): store.save_annotation(key,[])
    ann=store.save_annotation(key,[],True)
    assert ann['negative'] and ann['source']=='human'
    with pytest.raises(ValueError): store.save_annotation(key,[[1,1,20,20]],True)
    (tmp_path/'raw'/key).write_bytes(b'changed')
    with pytest.raises(ValueError,match='hash'): store.save_annotation(key,[],True)


@pytest.mark.parametrize('box',[[0,0,100,20],[1,1,1,20],[-1,0,20,20],[1,2,float('nan'),20]])
def test_invalid_boxes_rejected(tmp_path,box):
    store=DatasetStore(tmp_path); key=sample(store)
    with pytest.raises(ValueError): store.save_annotation(key,[box])


def test_unreviewed_is_never_exported_as_negative(tmp_path):
    store=DatasetStore(tmp_path); sample(store)
    with pytest.raises(ValueError,match='train:'): store.export(tmp_path/'release')
    assert not (tmp_path/'release').exists()
    with pytest.raises(ValueError): store.get('../outside.jpg')


def test_positive_only_validation_exports_with_visible_quality_warning(tmp_path):
    store=DatasetStore(tmp_path)
    seed=0
    for split,count in (('train',60),('val',16),('test',16)):
        for i in range(count):
            key=sample(store,session=split+str(i%2),number=i,split=split,seed=seed)
            seed+=1
            store.save_annotation(key,[[8,12,40,36]])
    sample(store,session='unreviewed',seed=500)
    data=Path(store.export(tmp_path/'release'))
    manifest=json.loads((data.parent/'review_manifest.json').read_text(encoding='utf8'))
    assert len(manifest['quality_warnings'])==3
    assert manifest['unreviewed_images_excluded']==1
    report=check_dataset(data)
    assert report['counts']==dict(train=60,val=16,test=16)
    assert len(report['quality_warnings'])==3 and not report['deployment_allowed']


def make_release(store):
    seed=0
    for split,count in (('train',60),('val',16),('test',16)):
        for i in range(count):
            key=sample(store,session=split+str(i%2),number=i,split=split,seed=seed)
            seed+=1
            store.save_annotation(key,[[8,12,40,36]] if i%3 else [],negative=not i%3)
    return Path(store.export(store.root/'release'))


def test_review_export_normalization_and_preflight_detects_label_tamper(tmp_path):
    store=DatasetStore(tmp_path); data=make_release(store)
    report=check_dataset(data)
    assert report['counts']==dict(train=60,val=16,test=16)
    assert not report['deployment_allowed'] and report['fpga_bottle_class_id']==39
    labels=list((data.parent/'labels'/'train').glob('*.txt'))
    positive=next(p for p in labels if p.read_text())
    assert positive.read_text()=='0 0.37500000 0.50000000 0.50000000 0.50000000'
    positive.write_text('0 .1 .1 .2 .2')
    with pytest.raises(ValueError,match='labels differ'): check_dataset(data)


def test_same_image_across_splits_is_rejected(tmp_path):
    store=DatasetStore(tmp_path)
    for split in ('train','val'):
        key=sample(store,session=split,split=split,seed=7)
        store.save_annotation(key,[[1,1,10,20]])
    with pytest.raises(ValueError,match='leaks'): store.export(tmp_path/'release')


def test_added_unreviewed_training_image_is_rejected(tmp_path):
    store=DatasetStore(tmp_path); data=make_release(store)
    (data.parent/'images/train/injected.jpg').write_bytes(b'not reviewed')
    with pytest.raises(ValueError,match='Unexpected image'): check_dataset(data)


def test_portal_annotation_http_and_cross_origin_guard(tmp_path):
    store=DatasetStore(tmp_path); key=sample(store)
    collector=Collector(store,'http://not-used.invalid')
    server=ThreadingHTTPServer(('127.0.0.1',0),handler(store,collector))
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    url=f'http://127.0.0.1:{server.server_port}'
    def post(path,payload,origin=None):
        headers={'Content-Type':'application/json'}
        if origin:headers['Origin']=origin
        return urllib.request.urlopen(urllib.request.Request(url+path,
            data=json.dumps(payload).encode(),headers=headers),timeout=2)
    try:
        with urllib.request.urlopen(url+'/') as r: assert '瓶子'.encode() in r.read()
        with post('/api/annotation',dict(id=key,boxes=[[8,12,40,36]])) as r:
            assert json.load(r)['source']=='human'
        with pytest.raises(urllib.error.HTTPError) as error:
            post('/api/capture',dict(scene='full_bottle',split='train',seconds=30),'http://evil.invalid')
        assert error.value.code==400 and not collector.status['running']
        with post('/api/export',{}) as r: pass
    except urllib.error.HTTPError as e:
        assert e.code==400  # insufficient dataset; no training/export silently started
    finally:
        server.shutdown();server.server_close();thread.join(timeout=2)


def test_only_explicit_local_addresses_bypass_system_proxy(monkeypatch):
    calls=[]
    class Response:
        headers={'X-Vision-Metadata':base64.b64encode(b'{"frame_id":1}').decode()}
        def __enter__(self):return self
        def __exit__(self,*args):pass
        def read(self):return b'\xff\xd8raw-test'
    monkeypatch.setattr(capture._LOCAL_OPENER,'open',lambda *a,**kw:(calls.append('local') or Response()))
    monkeypatch.setattr(capture.urllib.request,'urlopen',lambda *a,**kw:(calls.append('system') or Response()))
    capture.fetch_frame('http://192.168.137.129:8080')
    capture.fetch_frame('http://127.0.0.1:8091')
    capture.fetch_frame('https://example.org')
    assert calls==['local','local','system']
