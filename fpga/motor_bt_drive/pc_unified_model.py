"""Map preview and the fail-closed BTD6 navigation command contract."""

from __future__ import annotations

import json
import re
import sys
import math
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MAP = PROJECT_ROOT / "config" / "nav-map-2m.json"
SENSOR_STATUS_PATTERN = re.compile(
    r"I([01]) T([01]) D(\d{4}) H([01])"
    r"(?: F([0-9A-Fa-f]{2}) R([0-9A-Fa-f]{8})"
    r" P([0-9A-Fa-f]{8}) Y([0-9A-Fa-f]{8})"
    r"(?: W([0-9A-Fa-f]))?)?"
)
VISION_STATUS_PATTERN = re.compile(r"V([01]) L([01]) C([0-9A-Fa-f]{4}) K([0-9A-Fa-f]{8}) S([0-9A-Fa-f]{2}) A([01])")
TURN_STATUS_PATTERN = re.compile(r"Z([01]) Q([0-9A-Fa-f]{4}) S([0-9A-Fa-f]{2}) C([0-9A-Fa-f]{4}) T([0-9A-Fa-f]{4}) E([0-9A-Fa-f]{4})")
MOTOR_FAULT_PATTERN = re.compile(
    r"M([1-4]) T\d{3} A[+-]\d{3} D\d{4} F1 E([1-7]) X([+-]\d{3}) P(\d{4})"
)


def parse_motor_fault_snapshot(line):
    """Read first-trip evidence; E is a bit mask, X counts/10ms, P requested duty."""
    match = MOTOR_FAULT_PATTERN.fullmatch(line)
    if match is None:
        return None
    wheel, reason, speed, duty = map(int, match.groups())
    if duty > 1000:
        return None
    labels = [name for bit, name in ((1, '连续无反馈'), (2, '连续反向反馈'), (4, '超速计数')) if reason & bit]
    return dict(wheel=wheel, reason=reason, reason_text='、'.join(labels),
                speed=speed, duty=duty)


def parse_turn_status(line):
    match = TURN_STATUS_PATTERN.fullmatch(line)
    if match is None:
        return None
    active,seq,state,*angles = match.groups()
    values=[int(value,16) for value in angles]
    degrees=[math.degrees((v-65536 if v&32768 else v)/8192) for v in values]
    return dict(active=active=='1',sequence=int(seq,16),state=int(state,16),
                yaw_deg=degrees[0],target_deg=degrees[1],error_deg=degrees[2])
COCO_CLASSES = ('person bicycle car motorcycle airplane bus train truck boat traffic_light '
    'fire_hydrant stop_sign parking_meter bench bird cat dog horse sheep cow elephant bear '
    'zebra giraffe backpack umbrella handbag tie suitcase frisbee skis snowboard sports_ball '
    'kite baseball_bat baseball_glove skateboard surfboard tennis_racket bottle wine_glass cup '
    'fork knife spoon bowl banana apple sandwich orange broccoli carrot hot_dog pizza donut '
    'cake chair couch potted_plant bed dining_table toilet tv laptop mouse remote keyboard '
    'cell_phone microwave oven toaster sink refrigerator book clock vase scissors teddy_bear '
    'hair_drier toothbrush').split()


def parse_vision_status(line):
    match = VISION_STATUS_PATTERN.fullmatch(line)
    if match is None:
        return None
    fresh, visible, category, lock, state, active = match.groups()
    cid = int(category, 16)
    return dict(fresh=fresh == '1', visible=visible == '1', class_id=cid,
                class_name=COCO_CLASSES[cid].replace('_', ' ') if cid < len(COCO_CLASSES) else f'class {cid}',
                lock_id=int(lock, 16), state=int(state, 16), active=active == '1')
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def load_preview_map(path: Path = DEFAULT_MAP) -> tuple[dict, list[int]]:
    from scripts.build_nav_map import occupied_cells

    spec = json.loads(Path(path).read_text(encoding="utf-8"))
    if (spec.get("grid_cells") != 20 or spec.get("cell_m") != 0.1
            or spec.get("origin") != "bottom_left" or spec.get("map_id") != 0x2601):
        raise ValueError("地图版本、网格或坐标定义与 NAV3 预览不一致")
    cells = occupied_cells(spec)
    if len(cells) != 400:
        raise ValueError("占据地图长度错误")
    return spec, cells


def preview_goal(spec: dict, cells: list[int], x: int, y: int) -> list[tuple[int, int]]:
    from scripts.build_nav_map import shortest_path

    if type(x) is not int or type(y) is not int or not (0 <= x < 20 and 0 <= y < 20):
        raise ValueError("终点必须是 0～19 的整数格坐标")
    return shortest_path(spec, cells, (x, y))


def nav_send_supported() -> bool:
    """The legacy BTD5 image is manual-only; BTD6 adds the FPGA parser/BFS.

    The GUI still requires an explicit BTD6 firmware checkbox before writing a
    goal frame, so merely importing this helper cannot authorize a vehicle.
    """
    return False


def btd6_nav_supported(firmware_name: str) -> bool:
    """Return whether the selected BTD6-family image may receive goals.

    SIN1–SIN8 keep the BTD6 navigation parser and add the IMU/ToF front-end.
    """
    return firmware_name.strip().upper() in {"BTD6", "SIN1", "SIN2", "SIN3", "SIN4", "SIN5", "SIN6", "SIN7", "SIN8", "SIN9", "SIN10", "SIN11"}


def parse_sensor_status(line: str) -> tuple[str | None, ...] | None:
    """Parse legacy I/T/D/H, SIN2 F/R/P/Y, and SIN4 per-wheel W frames."""
    match = SENSOR_STATUS_PATTERN.fullmatch(line)
    return match.groups() if match else None


def route_codes(route: list[tuple[int, int]]) -> list[int]:
    """Convert adjacent grid cells to the FPGA's compact direction codes."""
    codes: list[int] = []
    mapping = {(0, 1): 0, (0, -1): 1, (-1, 0): 2, (1, 0): 3}
    for (x0, y0), (x1, y1) in zip(route, route[1:]):
        try:
            codes.append(mapping[(x1 - x0, y1 - y0)])
        except KeyError as exc:
            raise ValueError("路径必须由相邻格组成") from exc
    if len(codes) > 64:
        raise ValueError("FPGA 路径最多 64 步")
    return codes


def pack_btd6_route(seq: int, route: list[tuple[int, int]], x: int, y: int) -> bytes:
    """Build the v3 0x21 complete-route frame consumed by BTD6."""
    from src.comm.protocol import pack_nav_path

    if len(route) < 2 or route[-1] != (x, y):
        raise ValueError("路径终点与选定终点不一致")
    return pack_nav_path(seq, x, y, route_codes(route))


def pack_btd6_goal(seq: int, x: int, y: int) -> bytes:
    """Compatibility helper for the old 0x20 goal frame (not used by BTD6)."""
    from src.comm.protocol import pack_nav_goal

    return pack_nav_goal(seq, x, y)


def route_directions(route: list[tuple[int, int]]) -> str:
    """Human-readable route directions, used only for GUI logging/preview."""
    return "".join("FBLR"[code] for code in route_codes(route))
