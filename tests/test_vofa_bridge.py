import struct

from tools.vofa_bridge import CHANNELS, Telemetry, justfloat_packet


def test_parse_four_motor_line_and_channel_order():
    telemetry = Telemetry()
    assert telemetry.update_line("M3 T020 A-007 D0800 F1")
    values = telemetry.values()
    assert values[8:12] == [20.0, -7.0, 800.0, 1.0]
    assert len(values) == len(CHANNELS) == 16


def test_invalid_lines_are_ignored():
    telemetry = Telemetry()
    assert not telemetry.update_line("M3 BAD")
    assert telemetry.values()[8:12] == [0.0, 0.0, 0.0, 0.0]


def test_justfloat_tail_and_payload():
    packet = justfloat_packet([1.0, -2.0])
    assert struct.unpack("<ff", packet[:8]) == (1.0, -2.0)
    assert packet[-4:] == struct.pack("<I", 0x0000807F)
