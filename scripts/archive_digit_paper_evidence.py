"""Archive actual perception evidence without editing sealed FPGA archives."""
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board/digit_paper_settle_20261101'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    report=json.loads((OUT/'pi_stage_final/20261101_paper_v4_bounded_deployment_report.json').read_text())
    native=json.loads((OUT/'pi_stage_final/native_validation.json').read_text())
    live=json.loads((OUT/'live_card_bounded/validation.json').read_text())
    assert report['passed'] and native['passed'] and native['native_test_count']==99
    assert live['frame_count']==25 and live['detected_frames']==25
    assert live['identity_counts']['41990']==25
    for name,digest in report['candidate_sha256'].items():
        assert sha(ROOT/name)==sha(OUT/'pi_stage_final'/name)==digest
    for xml,count in [('windows_bounded.xml',101),('pi_stage_final/native_tests.xml',99)]:
        suites=ET.parse(OUT/xml).getroot().findall('testsuite')
        assert sum(int(s.attrib['tests']) for s in suites)==count
        assert all(int(s.attrib[k])==0 for s in suites for k in ('errors','failures','skipped'))
    assert len(report['frames'])==8
    assert all(s['task_mode']=='observe' and not s['mission_fpga']['active'] for s in report['frames'])
    files=['src/detection/printed_digit.py','src/detection/paper_digit_assist.py',
           'tests/test_digit_paper_assist.py','tests/test_r17_digit_stability.py',
           'tests/test_printed_digit_neighbor_filter.py','tests/test_printed_digit_recovery.py',
           'scripts/archive_digit_paper_evidence.py','scripts/capture_digit_paper_live.py',
           'scripts/deploy_pi_digit_paper.py','scripts/validate_digit_paper_native.py',
           'scripts/profile_digit_paper.py','scripts/stage_digit_paper.py','scripts/evaluate_digit_paper.py']
    for name in files:
        target=OUT/'final_sources'/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/name,target)
    manifest={p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*'))
              if p.is_file() and '__pycache__' not in p.parts and '.pytest_cache' not in p.parts
              and p.name not in ('SHA256.json','ARCHIVE_CHECK.json')}
    (OUT/'SHA256.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    reopened=json.loads((OUT/'SHA256.json').read_text())
    assert all(sha(OUT/n)==d for n,d in reopened.items())
    result=dict(passed=True,files=len(reopened),source_files=files,
                deployed_revision=report['revision'],windows_tests=101,pi_perception_tests=99,
                stationary_live_correct='25/25 digit6',motion_tested=False,fpga_changed=False,
                manifest_sha256=sha(OUT/'SHA256.json'))
    (OUT/'ARCHIVE_CHECK.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    print(json.dumps(result))


if __name__=='__main__':main()
