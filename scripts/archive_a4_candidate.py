"""Freeze a LOCAL candidate and evidence. Does not connect to the Pi or devices."""
from pathlib import Path
import hashlib,json,zipfile,platform
from datetime import datetime,timezone
import cv2,numpy

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board/a4_digit_candidate_20261031'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    OUT.mkdir(exist_ok=True)
    deployment=sorted(ROOT.glob('src/**/*.py'))+[ROOT/p for p in [
      'web/dashboard.html','web/a4-targets.html','assets/a4_digits_templates.json',
      'config/config-pi.yaml','config/config-pi-yolo-legacy.yaml','config/a4-geometry.pending.json',
      'scripts/build_nav_map.py','config/nav-map-2m.json','requirements-pi.txt']]
    evidence=[ROOT/p for p in [
      'tests/test_a4_digit.py','tests/test_a4_http.py',
      'scripts/build_a4_digit_templates.py','scripts/build_a4_digit_print_page.py',
      'scripts/archive_a4_candidate.py','scripts/verify_a4_identity_protocol.py',
      'fpga/motor_bt_drive/tb_a4_identity_protocol.sv',
      'fpga/motor_bt_drive/pc_unified_console.py',
      'output/board/a4_partial_python_final_20261031.xml',
      'output/board/a4_partial_synthetic_qa_20261031.png',
      'output/board/a4_identity_protocol_20261031/simulation.log',
      'output/board/SIN12_A4_DIGIT_MAINTENANCE_2026-10-31.md']]
    files=sorted(set(deployment+evidence))
    manifest={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in files}
    report=dict(created_utc=datetime.now(timezone.utc).isoformat(),hardware_access=False,
      deployed_to_pi=False,service_restart=False,production_rtl_modified=False,
      python=platform.python_version(),opencv=cv2.__version__,numpy=numpy.__version__,
      python_regression=dict(passed=158,failed=0,scope='named14 Python modules; synthetic printed pages and local HTTP only'),
      javascript='two inline scripts syntax checked with node:vm, not a browser visual/interaction acceptance',
      rtl_protocol='NOT RUN: ModelSim invalid license environment; byte-parser bench is unverified',
      pending=['Pi deployment','real printed-page recognition including reflections/angle/partial sequence',
               'Pi latency and capture age','actual ToF-paper association and camera/ToF calibration',
               'any FPGA visual-primary build/mapped/STA and field acceptance'],
      files_sha256=manifest)
    (OUT/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    with zipfile.ZipFile(OUT/'pi_source_candidate.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in deployment:z.write(p,str(p.relative_to(ROOT)))
        z.write(OUT/'manifest.json','candidate-manifest.json')
    with zipfile.ZipFile(OUT/'evidence.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in evidence:z.write(p,str(p.relative_to(ROOT)))
    for p in files:
        if sha(p)!=manifest[str(p.relative_to(ROOT)).replace('\\','/')]:raise RuntimeError('Source changed during archive')
    print(json.dumps(dict(files=len(files),deployment_files=len(deployment),candidate_sha256=sha(OUT/'pi_source_candidate.zip'),evidence_sha256=sha(OUT/'evidence.zip')),indent=2))

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=OUT)
    OUT=parser.parse_args().output.resolve()
    main()

