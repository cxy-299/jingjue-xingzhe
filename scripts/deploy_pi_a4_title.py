"""Reversible static A4 title update; no service restart, camera or serial API."""
import hashlib,json,os,shutil,sys,tempfile,urllib.request
from pathlib import Path
stage=Path(sys.argv[1]);expected=sys.argv[2]
root=Path('/home/pi/ling_shu_vision');target=root/'web/dashboard.html'
candidate=stage/'dashboard.html';backup=stage/'before_dashboard_title.html'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(target)=='aa3e73a6671b835c28a2c693880d87f35ec01d0fc9920c3350993c40f063b5c8','Live HTML changed; inspect first'
assert sha(candidate)==expected
assert not backup.exists()
shutil.copy2(target,backup)
def install(data):
    with tempfile.NamedTemporaryFile(dir=target.parent,delete=False) as f:
        tmp=Path(f.name);f.write(data);f.flush();os.fsync(f.fileno())
    os.chmod(tmp,0o644);os.replace(tmp,target)
report=dict(passed=False,previous_sha256=sha(backup),candidate_sha256=expected,
    backup=str(backup),service_restarted=False,motion_api_called=False,flash_written=False)
try:
    install(candidate.read_bytes())
    with urllib.request.urlopen('http://127.0.0.1:8080/?check=a4-title-20261031',timeout=5) as response:
        served=response.read()
    assert hashlib.sha256(served).hexdigest()==expected
    text=served.decode('utf8')
    assert '灵枢 · A4 数字靶标识别' in text
    assert '近距瓶身识别 V1' not in text and '红瓶二次筛选' not in text
    report['passed']=True
except BaseException as error:
    install(backup.read_bytes());report.update(error=str(error),rollback_restored=True);raise
finally:(stage/'title-deployment-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False))
