#!/usr/bin/env bash
# Run on Pi, not Windows. No site config replacement, no firmware programming.
set -euo pipefail
project=/home/pi/ling_shu_vision
archive=/home/pi/pi-sin11-mission-2026-10-27.tar
backup="/home/pi/before-sin11-$(date +%Y%m%d-%H%M%S)-$$.tgz"
cd "$project"
test -f "$archive"
# Check all regular archive files against the embedded manifest before service stop.
python3 - "$archive" <<'PY'
import hashlib,json,sys,tarfile
with tarfile.open(sys.argv[1]) as archive:
    manifest=json.load(archive.extractfile('SIN11_PI_MANIFEST.json'))
    if set(archive.getnames()) != set(manifest) | {'SIN11_PI_MANIFEST.json'}:
        raise SystemExit('Unexpected or missing archive members')
    for name,expected in manifest.items():
        member=archive.getmember(name)
        if not member.isfile() or name.startswith('/') or '..' in name.split('/'):
            raise SystemExit('Unsafe archive member: '+name)
        if hashlib.sha256(archive.extractfile(name).read()).hexdigest()!=expected:
            raise SystemExit('Hash mismatch: '+name)
print('Manifest OK; site config will be preserved.')
PY
tar -czf "$backup" src web scripts config
echo "Backup: $backup"
rollback() {
  echo 'Deployment failed; restoring previous files.' >&2
  tar -xf "$backup" -C "$project"
  sudo systemctl restart ling-shu-vision-gui.service || true
}
trap rollback ERR
sudo systemctl stop ling-shu-vision-gui.service
tar -xf "$archive" -C "$project"
python3 -m py_compile src/web_gui.py src/comm/protocol.py src/comm/mission.py src/detection/semantic_mission.py
sudo systemctl start ling-shu-vision-gui.service
for attempt in $(seq 1 45); do
  if curl -fsS --max-time 2 http://127.0.0.1:8080/health; then
    trap - ERR
    echo 'SIN11 Pi files deployed. Open the Pi IP:8080; prepare a NEW mission.'
    exit 0
  fi
  sleep 2
done
echo 'HTTP startup timeout; see journalctl -u ling-shu-vision-gui.service -n 60 --no-pager' >&2
false
