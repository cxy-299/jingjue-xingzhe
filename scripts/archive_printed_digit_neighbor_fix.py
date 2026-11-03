"""Independent software-only fix evidence, preserving R15 hardware archives."""
from pathlib import Path
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/board"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    deploy = json.loads((OUT / "R15_DIGIT_NEIGHBOR_DEPLOYMENT_20261101.json").read_text(encoding="utf-8-sig"))
    native = json.loads((OUT / "R15_DIGIT_NEIGHBOR_NATIVE_20261101.json").read_text(encoding="utf-8-sig"))
    assert deploy["passed"] and native["passed"]
    assert deploy["changed_files"] == ["src/detection/printed_digit.py"]
    assert native["source_sha256"] == deploy["candidate_sha256"] == sha(ROOT / "src/detection/printed_digit.py")
    for name, count in (("r15_digit_neighbor_final_20261101.xml", 142), ("r15_digit_neighbor_native_20261101.xml", 24)):
        root = ET.parse(OUT / name).getroot()
        suite = root if root.tag == "testsuite" else root.find("testsuite")
        assert int(suite.attrib["tests"]) == count
        assert all(int(suite.attrib[k]) == 0 for k in ("errors", "failures", "skipped"))
    hardware = json.loads((OUT / "sin12_hdmi_r15_build_sources.json").read_text(encoding="utf-8-sig"))
    assert len(hardware) == 57 and all(sha(ROOT / p) == h for p,h in hardware.items())
    archive = OUT / "digit_neighbor_fix_20261101"
    archive.mkdir(exist_ok=False)
    selected = ["src/detection/printed_digit.py", "tests/test_printed_digit_neighbor_filter.py",
                "tests/test_printed_digit_recovery.py", "scripts/verify_printed_digit_neighbor_pi.py",
                "scripts/deploy_pi_digit_neighbor_fix.py", "scripts/archive_printed_digit_neighbor_fix.py"]
    selected += [p.relative_to(ROOT).as_posix() for p in (ROOT / "tests/fixtures/a4_whitewall_20261031").glob("*") if p.is_file()]
    for name in selected:
        target = archive / "sources" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    for pattern in ("r15_digit_neighbor_*20261101*", "R15_DIGIT_NEIGHBOR_*20261101*",
                    "r15_digit_diagnostic_20261101*", "SIN12_R15_DIGIT_DIAGNOSIS_2026-11-01.md",
                    "SIN12_DIGIT_NEIGHBOR_MAINTENANCE_2026-11-01.md"):
        for path in OUT.glob(pattern):
            if path.is_file(): shutil.copy2(path, archive / path.name)
    report = dict(deployed=True, revision=deploy["revision"], source_sha256=deploy["candidate_sha256"],
                  changed_production_files=deploy["changed_files"], protected_files_count=len(deploy["preserved_sha256"]),
                  pc_tests_passed=142, native_tests_passed=24, native_saved_zero_frames_passed=6,
                  backup=deploy["backup"], hardware_sources_unchanged=57, fpga_reconfigured=False,
                  motion_started=False, prior_task_context_cleared_to_observe=True,
                  original_build_archive_unchanged=True,
                  limitations=["No card in post-deployment live view; live positive recognition pending",
                      "Six saved real scenes all digit zero; digits1-9 covered synthetically, not full field accuracy",
                      "No model training, score threshold relaxation, range inference, or changed tracking/mission logic"],
                  retained_failures=["initial test import collection error", "11 reproduction failures before fix",
                      "two clipped-neighbour false positives in first candidate, fixed before deployment"])
    (archive / "VERIFICATION.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf8")
    hashes = {p.relative_to(archive).as_posix():sha(p) for p in archive.rglob("*") if p.is_file()}
    (archive / "SHA256.json").write_text(json.dumps(hashes, indent=2), encoding="utf8")
    assert all(sha(archive / p) == h for p,h in hashes.items())
    print(json.dumps(dict(archive=str(archive), files=len(hashes), **report), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
