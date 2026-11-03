from src.comm.pid_tuning import mission_lease_ms


def test_only_explicit_r15_changes_mission_lease_not_unknown_or_legacy():
    assert mission_lease_ms(15) == 600
    assert mission_lease_ms(16) == 600
    for version in (*range(4, 15), 0, 17, 255):
        assert mission_lease_ms(version) == 300


def test_production_r15_enables_600ms_only_in_mission_instance():
    from pathlib import Path
    source = (Path(__file__).resolve().parents[1] /
              "fpga/motor_bt_drive/acg720_motor_bt_drive.v").read_text(encoding="utf-8")
    assert source.count(".LEASE_MS(REV5_ENABLE>=11?600:300)") == 1
    assert "vision_mission_guard #(" in source
