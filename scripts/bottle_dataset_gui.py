"""Local, read-only-to-Pi collection and manual annotation portal."""
import argparse
import datetime
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time
from urllib.parse import urlparse, parse_qs

from scripts.bottle_dataset import DatasetStore, SCENES, SPLITS, atomic_json
from scripts.capture_pi_training_frames import fetch_frame


class Collector:
    def __init__(self, store, url):
        self.store, self.url = store, url
        self.lock = threading.Lock()
        self.status = dict(running=False, count=0, error='', session='')

    def start(self, scene, split, seconds):
        if scene not in SCENES or split not in SPLITS or type(seconds) is not int or not 5 <= seconds <= 120:
            raise ValueError('Choose scene, split and 5..120 seconds')
        with self.lock:
            if self.status['running']:
                raise ValueError('Collection is already running')
            session = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
            self.status = dict(running=True, count=0, error='', session=session)
        threading.Thread(target=self._run,args=(session,scene,split,seconds),daemon=True).start()

    def _run(self, session, scene, split, seconds):
        out = self.store.root/'raw'/session
        try:
            out.mkdir(parents=True,exist_ok=False)
            atomic_json(out/'session.json',dict(split=split,scene=scene))
            deadline = time.monotonic()+seconds
            hashes = set()
            with (out/'manifest.jsonl').open('w',encoding='utf8') as manifest:
                while time.monotonic() < deadline:
                    data, meta = fetch_frame(self.url)  # HTTP GET only
                    digest = hashlib.sha256(data).hexdigest()
                    if digest not in hashes:
                        with self.lock: count = self.status['count']
                        name=f'{count:05d}.jpg'; (out/name).write_bytes(data)
                        manifest.write(json.dumps(dict(image=name,session=session,scene=scene,
                            sha256=digest,metadata=meta,annotation_status='unreviewed',
                            predictions_are_labels=False),ensure_ascii=False)+'\n')
                        manifest.flush(); hashes.add(digest)
                        with self.lock: self.status['count'] += 1
                    time.sleep(1)
        except Exception as error:
            with self.lock: self.status['error'] = str(error)
        finally:
            with self.lock: self.status['running'] = False


def handler(store, collector):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, data, status=200, mime='application/json; charset=utf-8'):
            if not isinstance(data,bytes): data=json.dumps(data,ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header('Content-Type',mime); self.send_header('Content-Length',str(len(data)))
            self.send_header('Cache-Control','no-store'); self.end_headers(); self.wfile.write(data)

        def do_GET(self):
            try:
                url = urlparse(self.path)
                if url.path == '/':
                    return self.reply((Path(__file__).resolve().parents[1]/'web/bottle_dataset.html').read_bytes(),
                                      mime='text/html; charset=utf-8')
                if url.path == '/api/items':
                    with collector.lock: status=dict(collector.status)
                    return self.reply(dict(items=store.items(),collection=status))
                if url.path == '/image':
                    item=store.get(parse_qs(url.query).get('id',[''])[0])
                    return self.reply(store.image_path(item).read_bytes(),mime='image/jpeg')
                self.reply(dict(error='Not found'),404)
            except (ValueError, OSError) as error:
                self.reply(dict(error=str(error)),400)

        def do_POST(self):
            try:
                # Local interaction only. Reject browser requests from other sites.
                if self.headers.get('Origin') not in (None, 'http://'+self.headers.get('Host','')):
                    raise ValueError('Cross-origin request refused')
                if self.headers.get('Content-Type','').split(';')[0] != 'application/json':
                    raise ValueError('JSON required')
                length=int(self.headers.get('Content-Length',0))
                if not 0 < length <= 20000: raise ValueError('Invalid request length')
                data=json.loads(self.rfile.read(length))
                if self.path == '/api/capture':
                    collector.start(data['scene'],data['split'],data['seconds'])
                    return self.reply(dict(started=True))
                if self.path == '/api/annotation':
                    with collector.lock:
                        ann=store.save_annotation(data['id'],data['boxes'],data.get('negative',False))
                    return self.reply(ann)
                if self.path == '/api/export':
                    with collector.lock:
                        if collector.status['running']: raise ValueError('Wait for capture to finish')
                        name=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
                        result=store.export(store.root/'releases'/name)
                        report=json.loads((Path(result).parent/'review_manifest.json').read_text(encoding='utf8'))
                    return self.reply(dict(dataset=result, counts=report['counts'],
                                           warnings=report.get('quality_warnings', []),
                                           unreviewed_excluded=report.get('unreviewed_images_excluded',0)))
                self.reply(dict(error='Not found'),404)
            except (ValueError,KeyError,OSError) as error:
                self.reply(dict(error=str(error)),400)

        def log_message(self,*args): pass
    return Handler


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,default=Path('data/field_bottle'))
    p.add_argument('--url',default='http://192.168.137.129:8080')
    p.add_argument('--port',type=int,default=8091)
    a=p.parse_args()
    store=DatasetStore(a.root); collector=Collector(store,a.url)
    server=ThreadingHTTPServer(('127.0.0.1',a.port),handler(store,collector))
    print(f'Bottle dataset: http://127.0.0.1:{a.port} (Pi GET only)',flush=True)
    try: server.serve_forever()
    finally: server.server_close()


if __name__=='__main__': main()
