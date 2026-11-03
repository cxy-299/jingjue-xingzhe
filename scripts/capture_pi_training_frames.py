"""Passive raw image collection from the existing vision service; no motion POST.

Predictions are review metadata ONLY, never YOLO ground-truth label files.
Keep each session together when later splitting train/validation/test.
"""
import argparse
import base64
import datetime
import hashlib
import ipaddress
import json
from pathlib import Path
import time
import urllib.request
from urllib.parse import urlparse

_LOCAL_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def fetch_frame(base_url):
    url = base_url.rstrip('/')+'/snapshot-raw.jpg'
    host = urlparse(url).hostname or ''
    try:
        local = ipaddress.ip_address(host).is_private
    except ValueError:
        local = host == 'localhost'
    # Explicit local Pi/loopback addresses do not need the Windows Internet
    # proxy (~5s/request observed). Do not change global proxies or remote URLs.
    open_url = _LOCAL_OPENER.open if local else urllib.request.urlopen
    with open_url(url, timeout=5) as r:
        metadata = json.loads(base64.b64decode(r.headers['X-Vision-Metadata']))
        data = r.read()
    if not data.startswith(b'\xff\xd8') or metadata.get('frame_id') is None:
        raise ValueError('Missing raw JPEG or frame metadata')
    return data, metadata


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--url', default='http://192.168.137.129:8080')
    p.add_argument('--scene', required=True, help='Describe distance/lighting/occlusion; not a ground-truth label')
    p.add_argument('--seconds', type=float, default=30)
    p.add_argument('--interval', type=float, default=1)
    p.add_argument('--out', type=Path, default=Path('data/field_bottle/raw'))
    a = p.parse_args()
    if not 0 < a.seconds <= 600 or a.interval < .5:
        p.error('seconds must be 0..600, interval at least .5 seconds')
    session = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    out = a.out/session
    out.mkdir(parents=True, exist_ok=False)
    seen, hashes, count = set(), set(), 0
    until = time.monotonic()+a.seconds
    with (out/'manifest.jsonl').open('w', encoding='utf8') as manifest:
        while time.monotonic() < until:
            data, meta = fetch_frame(a.url)
            identity = (meta['frame_id'], meta.get('frame_captured_unix_s'))
            digest = hashlib.sha256(data).hexdigest()
            if identity not in seen and digest not in hashes:
                name = f'{count:05d}.jpg'
                (out/name).write_bytes(data)
                manifest.write(json.dumps(dict(image=name, session=session, scene=a.scene,
                    collected_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    sha256=digest, annotation_status='unreviewed', predictions_are_labels=False,
                    metadata=meta), ensure_ascii=False)+'\n')
                manifest.flush()
                seen.add(identity); hashes.add(digest); count += 1
            time.sleep(a.interval)
    print(json.dumps(dict(session=str(out.resolve()), raw_images=count, labels_created=0,
                          motion_commands_sent=False), ensure_ascii=False))


if __name__ == '__main__':
    main()
