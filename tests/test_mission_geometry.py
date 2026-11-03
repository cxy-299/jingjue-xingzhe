from dataclasses import replace
import struct
import pytest
from src.core.messages import Detection, TargetObservation
from src.core.visual_alignment import VisualAlignmentResult
from src.detection.visual_tof_geometry import VisualToFCalibration
from src.detection.mission_geometry import MissionGeometryReporter
from src.comm.protocol import pack_visual_primary_observation, pack_mission_observation, parse_frame


def reporter():
    # SYNTHETIC, not field calibration. Never deploy these values.
    return MissionGeometryReporter(VisualToFCalibration('synthetic-only',640,480,
        500.,500.,320.,240.,200.,3.,0.,0.,0.,150.,5000.))


def bottle():
    return Detection(39,'bottle',.9,270.,140.,370.,340.,640,480)


def test_advisory_estimate_has_parallax_uncertainty_not_authority():
    g=reporter().observe(bottle(),age_ms=23,confirmed=True)
    assert g['coarse_mm']==500 and g['uncertainty_mm']==200
    assert g['yaw_left_cdeg']==34 and g['beam_inside']
    assert not g['visibility_verified'] and not g['distance_authoritative']


@pytest.mark.parametrize('age',[-1,280,300,580,float('nan')])
def test_inference_latency_not_hidden(age):
    assert reporter().observe(bottle(),age_ms=age,confirmed=True) is None


@pytest.mark.parametrize('changes',[dict(y1=0),dict(x1=0),dict(confidence=.4),dict(frame_width=320)])
def test_partial_or_unreliable_view_does_not_gain_range(changes):
    assert reporter().observe(replace(bottle(),**changes),age_ms=0,confirmed=True) is None


def test_bearing_sign_and_unconfirmed():
    r=reporter()
    assert r.observe(bottle(),age_ms=0,confirmed=False) is None
    assert r.observe(replace(bottle(),x1=400.,x2=500.),age_ms=0,confirmed=True)['yaw_left_cdeg']<0
    assert r.observe(replace(bottle(),x1=150.,x2=250.),age_ms=0,confirmed=True)['yaw_left_cdeg']>0


def test_default_r12_mode_and_missing_calibration():
    assert MissionGeometryReporter.from_config({}) is None
    with pytest.raises(ValueError): MissionGeometryReporter.from_config({'mission_geometry':{'enabled':True}})


def test_new_packet_is_atomic_extension_and_legacy_unchanged():
    obs=TargetObservation.from_detection(123,bottle())
    align=VisualAlignmentResult('CENTERED',0,0,0,'test')
    g=reporter().observe(bottle(),age_ms=10,confirmed=True)
    old=parse_frame(pack_mission_observation(3,obs,align,7,2,True,1))
    new=parse_frame(pack_visual_primary_observation(3,obs,align,7,2,True,1,geometry=g))
    assert new['msg_type']==0x16 and len(new['payload'])==44
    assert new['payload'][:35]==old['payload']
    assert struct.unpack('<BhHHH',new['payload'][35:])==(3,34,500,200,10)
    hold=parse_frame(pack_visual_primary_observation(3,obs,align,7,2,True,1))
    assert hold['payload'][35:]==struct.pack('<BhHHH',0,0,0,0,65535)


@pytest.mark.parametrize('key,value',[('observation_age_ms',280),('uncertainty_mm',500),
    ('yaw_left_cdeg',4501),('coarse_mm',10001)])
def test_packet_rejects_invalid_geometry(key,value):
    obs=TargetObservation.from_detection(0,bottle());g=reporter().observe(bottle(),age_ms=0,confirmed=True)
    g[key]=value
    with pytest.raises(ValueError):
        pack_visual_primary_observation(0,obs,VisualAlignmentResult('CENTERED',0,0,0,''),0,2,True,1,geometry=g)


def test_queue_age_and_class_calibration_cannot_be_ignored():
    r=MissionGeometryReporter(reporter().calibration,capture_age_bound_ms=90)
    assert r.observe(bottle(),age_ms=200,confirmed=True) is None
    assert r.observe(replace(bottle(),class_name='person'),age_ms=0,confirmed=True) is None
    assert r.observe(bottle(),age_ms=True,confirmed=True) is None


def test_forward_offset_converts_optical_z_to_tof_ray_length():
    r=MissionGeometryReporter(replace(reporter().calibration,tof_z_mm=30))
    g=r.observe(bottle(),age_ms=0,confirmed=True)
    assert g['coarse_optical_z_mm']==500 and g['coarse_mm']==470


def test_half_uncertainty_rounding_is_wire_safe():
    r=MissionGeometryReporter(reporter().calibration,uncertainty_fraction=.5)
    g=r.observe(replace(bottle(),y2=339.5),age_ms=0,confirmed=True)
    assert g['uncertainty_mm']<=g['coarse_mm']//2


