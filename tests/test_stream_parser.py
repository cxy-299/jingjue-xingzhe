from src.comm.protocol import pack_heartbeat
from src.comm.stream_parser import FrameStreamParser


def test_stream_parser_handles_noise_and_fragmented_frames():
    first = pack_heartbeat(1, 100)
    second = pack_heartbeat(2, 200)
    parser = FrameStreamParser()

    assert parser.feed(b'noise\xAA') == []
    assert parser.feed(first[1:7]) == []
    frames = parser.feed(first[7:] + second)

    assert [frame['seq'] for frame in frames] == [1, 2]
    assert parser.bad_frames == 0


def test_stream_parser_recovers_after_crc_error():
    bad = bytearray(pack_heartbeat(3, 300))
    bad[-1] ^= 0xFF
    good = pack_heartbeat(4, 400)
    parser = FrameStreamParser()

    frames = parser.feed(bytes(bad) + good)
    assert [frame['seq'] for frame in frames] == [4]
    assert parser.bad_frames >= 1
