"""File-only Pi verification against its actual OpenCV and production dependencies."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time


def main():
    stage = Path(__file__).resolve().parent
    root = Path("/home/pi/ling_shu_vision")
    sys.path.insert(0, str(root))
    candidate = stage / "src/detection/printed_digit.py"
    spec = importlib.util.spec_from_file_location("src.detection.printed_digit", candidate)
    module = importlib.util.module_from_spec(spec)
    # Only this isolated verifier process imports the staged candidate.
    # The running service and its source files are not modified here.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    import cv2
    import numpy as np
    import pytest
    from src.core.a4_targets import CLASS_BASE
    result = pytest.main([str(stage / "tests/test_printed_digit_neighbor_filter.py"),
                          "-q", "--tb=short", "--junitxml=" + str(stage / "native_tests.xml")])
    assert result == 0, "Native candidate regression failed"
    frames = []
    detector = module.PrintedDigitDetector()
    for path in sorted((stage / "tests/fixtures/a4_whitewall_20261031").glob("*")):
        frame = cv2.imread(str(path))
        assert frame is not None, path.name
        started = time.monotonic()
        detections = detector.detect(frame)
        assert len(detections) == 1 and detections[0].class_id == CLASS_BASE, path.name
        frames.append(dict(file=path.name, class_id=detections[0].class_id,
                           template_score=detections[0].confidence,
                           elapsed_ms=(time.monotonic() - started) * 1000))
    assert len(frames) == 6
    report = dict(passed=True, source_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest(),
                  revision=detector.revision, python=sys.version, opencv=cv2.__version__,
                  numpy=np.__version__, native_test_count=24, real_saved_frames=frames,
                  hardware_access=False, service_modified=False,
                  scope="File-only candidate process; six saved zero scenes and synthetic regressions, not live motion acceptance")
    (stage / "native_validation.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
