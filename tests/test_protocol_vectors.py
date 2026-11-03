from pathlib import Path

from src.comm.protocol import pack_heartbeat, pack_vision_result
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentResult


def test_python_bytes_used_by_rtl_testbench_are_current():
    """保证 RTL 跨语言 testbench 的字节流没有与 Python 发包代码脱节。"""
    golden = Path(__file__).resolve().parents[1] / "fpga" / "acg720_uart_bringup" / "python_uart_frames.mem"
    rows = [bytes.fromhex(line) for line in golden.read_text().splitlines()]
    bottle = TargetObservation(1000, True, 39, "bottle", .9, 3000, 5000, 1800, 3600)
    left = VisualAlignmentResult("ALIGN_LEFT", 0, 0, -.4, "test")
    lost = TargetObservation(2000, False)
    search = VisualAlignmentResult("SEARCH", 0, 0, 0, "lost")
    assert rows == [
        pack_heartbeat(10, 1234),
        pack_vision_result(11, bottle, left, 77),
        pack_vision_result(12, lost, search, 78),
    ]
