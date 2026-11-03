"""Provisional forward-only R16 calibration; no hardware serial ports."""
from pathlib import Path
import pytest
from src.comm.autonav import counts_per_cell_for_version, pack_autonav_goal
from src.comm.protocol import parse_frame
ROOT=Path(__file__).resolve().parents[1]
@pytest.mark.parametrize('version',range(5,16))
def test_old_firmware_counts_unchanged(version):
    assert counts_per_cell_for_version(version)==1000
@pytest.mark.parametrize('version',[None,0,4,19,True,'16'])
def test_unknown_firmware_never_guesses_counts(version):
    with pytest.raises(ValueError): counts_per_cell_for_version(version)
def test_r16_wire_contract():
    counts=counts_per_cell_for_version(16)
    assert counts==333
    frame=parse_frame(pack_autonav_goal(9,(17,2),(17,9),counts,0,True))
    assert int.from_bytes(frame['payload'][6:8],'little')==333
    assert frame['payload'][2:6]==bytes([17,2,17,9])
def test_scope_and_provisional_status():
    drive=(ROOT/'fpga/motor_bt_drive/acg720_motor_bt_drive.v').read_text(encoding='utf8')
    assert 'AUTO_GRID_COUNTS=REV5_ENABLE>=14 ? 500 : REV5_ENABLE>=12 ? 333 : NAV_CELL_COUNTS' in drive
    assert 'nav_route_executor #(.CELL_COUNTS(NAV_CELL_COUNTS)' in drive
    assert '.counts_i(auto_request?counts:AUTO_GRID_COUNTS[15:0])' in drive
    assert '"ground_distance_calibrated": false' in (ROOT/'config/robot-geometry.json').read_text(encoding='utf8')
