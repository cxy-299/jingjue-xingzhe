import base64
import json
from pathlib import Path
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import cv2
import numpy as np
import pytest

from scripts.calibrate_visual_aim import suggest_aim
from scripts.capture_pi_training_frames import fetch_frame
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentController
from src.web_gui import DashboardState, make_handler, create_aligner


def test_empirical_calibration_is_signed_camera_reference_not_range_correction():
    report = suggest_aim(dict(width=640, height=480, distance_mm=300,
                             points=[[350,230],[352,232],[351,231]]))
    assert report['suggested_visual_alignment'] == dict(center_target=5484, aim_y_target=4812)
    assert not report['automatic_application']
    aligner = create_aligner({'visual_alignment': {
        **report['suggested_visual_alignment'], 'target_confirm_frames': 1}})
    observation = TargetObservation(1, True, 39, 'bottle', .9, 5484, 4812, 1000, 5000)
    assert aligner.update(observation).center_error == 0
    observation.cx = 5000
    assert aligner.update(observation).center_error < 0
    assert observation.cx == 5000  # no mutation of physical bbox coordinates


@pytest.mark.parametrize('points', [[[20,20]], [[2,2],[100,2],[2,2]],
    [[-1,200],[0,200],[1,200]], [[700,200]]*3, [[float('nan'),2]]*3])
def test_bad_calibration_is_rejected(points):
    with pytest.raises(ValueError):
        suggest_aim(dict(width=640, height=480, distance_mm=300, points=points))


@pytest.mark.parametrize('value', [-1, 10001, float('nan'), float('inf')])
def test_invalid_runtime_reference_is_rejected(value):
    with pytest.raises(ValueError):
        VisualAlignmentController(center_target=value)


def test_raw_endpoint_is_unannotated_and_metadata_is_same_frame(tmp_path):
    state = DashboardState()
    raw = np.full((48,64,3), 70, dtype=np.uint8)
    annotated = np.full_like(raw, 200)
    ok, encoded = cv2.imencode('.jpg', annotated)
    assert ok
    server = ThreadingHTTPServer(('127.0.0.1',0), make_handler(state, Path('web/dashboard.html')))
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    url = f'http://127.0.0.1:{server.server_port}'
    try:
        with pytest.raises(urllib.error.HTTPError) as err:
            fetch_frame(url)
        assert err.value.code == 503
        state.update(encoded.tobytes(), dict(frame_id=91, frame_captured_unix_s=10,
            detections=[], alignment_center_target=5500), raw_frame=raw)
        raw[:] = 0  # frame handed back to camera/drawing code cannot change saved raw
        data, meta = fetch_frame(url)
        decoded = cv2.imdecode(np.frombuffer(data,np.uint8), cv2.IMREAD_COLOR)
        assert abs(float(decoded.mean())-70) < 1
        assert meta['frame_id'] == 91 and meta['alignment_center_target'] == 5500
        assert state.task_revision == 0 and state.pending_nav_goal is None
        with urllib.request.urlopen(url+'/snapshot.jpg') as r:
            assert r.read() == encoded.tobytes()
        state.update(encoded.tobytes(), dict(frame_id=92), raw_frame=np.full_like(raw,90))
        _, meta = fetch_frame(url)
        assert meta['frame_id'] == 92
    finally:
        server.shutdown(); server.server_close(); thread.join(timeout=2)
