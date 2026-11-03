"""从唯一地图定义生成 FPGA 占据存储初始化文件，并供 PDF/UI 测试复用。"""

from __future__ import annotations

import json
import math
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
FPGA_NEIGHBOR_ORDER = ((0, 1), (-1, 0), (0, -1), (1, 0))
MAP_FILE = ROOT / "config" / "nav-map-2m.json"
MEM_FILE = ROOT / "fpga" / "nav" / "nav_map_20x20.mem"


def load_map(path: Path = MAP_FILE) -> dict:
    spec = json.loads(path.read_text(encoding="utf-8"))
    n = spec["grid_cells"]
    assert n == 20 and spec["cell_m"] == 0.1 and spec["size_m"] == 2.0
    assert spec["origin"] == "bottom_left"
    assert spec["map_id"] == 0x2601
    for obstacle in spec["obstacles"]:
        x, y = obstacle["min_cell"]
        w, h = obstacle["size_cells"]
        assert 0 <= x < n and 0 <= y < n and w > 0 and h > 0
        assert x + w <= n and y + h <= n
    return spec


def occupied_cells(spec: dict) -> list[int]:
    """每格中心与边界/障碍实体至少相距 15 cm 才允许车体中心进入。"""
    n = spec["grid_cells"]
    step = spec["cell_m"]
    size = spec["size_m"]
    margin = spec["inflation_radius_m"]
    cells = [0] * (n * n)
    for y in range(n):
        for x in range(n):
            cx, cy = (x + 0.5) * step, (y + 0.5) * step
            if min(cx, cy, size - cx, size - cy) < margin - 1e-9:
                cells[y * n + x] = 1
                continue
            for obstacle in spec["obstacles"]:
                ox, oy = obstacle["min_cell"]
                w, h = obstacle["size_cells"]
                x0, x1 = ox * step, (ox + w) * step
                y0, y1 = oy * step, (oy + h) * step
                dx = max(x0 - cx, 0.0, cx - x1)
                dy = max(y0 - cy, 0.0, cy - y1)
                if math.hypot(dx, dy) <= margin + 1e-9:
                    cells[y * n + x] = 1
                    break
    return cells


def shortest_path(spec: dict, cells: list[int], goal: tuple[int, int]) -> list[tuple[int, int]]:
    """从固定起点规划；动态重规划请使用 ``shortest_path_from``。"""
    return shortest_path_from(spec, cells, tuple(spec["start_cell"]), goal)


def shortest_path_from(spec: dict, cells: list[int], start: tuple[int, int],
                       goal: tuple[int, int], *,
                       neighbor_order=((1, 0), (-1, 0), (0, 1), (0, -1))) -> list[tuple[int, int]]:
    """四邻域 BFS，可从 ToF 停车后的当前格重新规划。"""
    n = spec["grid_cells"]
    sx, sy = start
    gx, gy = goal
    if not (0 <= sx < n and 0 <= sy < n and 0 <= gx < n and 0 <= gy < n):
        return []
    start, dest = sy * n + sx, gy * n + gx
    if cells[start] or cells[dest]:
        return []
    parent = [-1] * (n * n)
    parent[start] = start
    queue = deque([start])
    while queue and parent[dest] == -1:
        cur = queue.popleft()
        x, y = cur % n, cur // n
        for dx, dy in neighbor_order:
            nx, ny = x + dx, y + dy
            if not (0 <= nx < n and 0 <= ny < n):
                continue
            nxt = ny * n + nx
            if cells[nxt] or parent[nxt] != -1:
                continue
            parent[nxt] = cur
            queue.append(nxt)
    if parent[dest] == -1:
        return []
    result = []
    cur = dest
    while cur != start:
        result.append((cur % n, cur // n))
        cur = parent[cur]
    result.append((sx, sy))
    result.reverse()
    return result


def add_dynamic_obstacle(cells: list[int], grid_cells: int,
                         center: tuple[int, int], radius_cells: int = 1) -> list[int]:
    """Return a safety-inflated occupancy copy for a newly detected obstacle."""
    if len(cells) != grid_cells * grid_cells:
        raise ValueError("occupancy length does not match grid")
    cx, cy = center
    if not (0 <= cx < grid_cells and 0 <= cy < grid_cells):
        raise ValueError("dynamic obstacle is outside the map")
    if radius_cells < 0:
        raise ValueError("radius_cells must be non-negative")
    updated = list(cells)
    for y in range(max(0, cy - radius_cells), min(grid_cells, cy + radius_cells + 1)):
        for x in range(max(0, cx - radius_cells), min(grid_cells, cx + radius_cells + 1)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius_cells ** 2:
                updated[y * grid_cells + x] = 1
    return updated


def main() -> None:
    spec = load_map()
    occupied = occupied_cells(spec)
    start = tuple(spec["start_cell"])
    example = tuple(spec["example_goal_cell"])
    assert not occupied[start[1] * 20 + start[0]], "起点落入安全膨胀区"
    route = shortest_path(spec, occupied, example)
    assert route, "PDF 示例终点必须可达"
    # 地址 = row*20+col，row 0 在地图最下方；每行一位 0/1 供 $readmemh 初始化。
    MEM_FILE.parent.mkdir(parents=True, exist_ok=True)
    MEM_FILE.write_text("".join(f"{bit:x}\n" for bit in occupied), encoding="ascii")
    reachable = sum(bool(shortest_path(spec, occupied, (x, y))) for y in range(20) for x in range(20))
    print(f"map_id=0x{spec['map_id']:04X} occupied={sum(occupied)} reachable={reachable} example_steps={len(route)-1}")


if __name__ == "__main__":
    main()
