"""从 ModelSim 导出的 VCD 绘制可读的导航验收波形图。"""

from collections import defaultdict
import os
from pathlib import Path

# 将字体缓存放到项目内，避免只读用户配置目录影响离线出图。
ROOT = Path(__file__).resolve().parent.parent
MPL_CACHE = ROOT / "tmp" / "matplotlib"
MPL_CACHE.mkdir(parents=True, exist_ok=True)
os.environ["MPLCONFIGDIR"] = str(MPL_CACHE)

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


VCD = ROOT / "output" / "sim" / "acg720_nav_preview.vcd"
PNG = ROOT / "output" / "sim" / "acg720_nav_preview_wave.png"


def read_vcd(path):
    """只解析该图所需的标准 VCD 变量定义和时间/取值变化。"""
    names = {}
    scopes = []
    changes = defaultdict(list)
    time_ps = 0
    in_header = True
    for raw in path.read_text(encoding="ascii", errors="replace").splitlines():
        line = raw.strip()
        if in_header:
            parts = line.split()
            if line.startswith("$scope"):
                scopes.append(parts[2])
            elif line.startswith("$upscope"):
                scopes.pop()
            elif line.startswith("$var"):
                names[parts[3]] = "/".join(scopes + [parts[4] + (parts[5] if len(parts) > 6 else "")])
            elif line == "$enddefinitions $end":
                in_header = False
            continue
        if line.startswith("#"):
            time_ps = int(line[1:])
        elif line[:1] in ("0", "1", "x", "z") and len(line) > 1:
            if line[0] in "01":
                changes[names.get(line[1:], line[1:])].append((time_ps / 1e9, int(line[0])))
        elif line.startswith("b"):
            bits, symbol = line[1:].split()
            if all(bit in "01" for bit in bits):
                changes[names.get(symbol, symbol)].append((time_ps / 1e9, int(bits, 2)))
    return changes


def value_at(events, moment):
    value = 0
    for time_ms, new in events:
        if time_ms > moment:
            break
        value = new
    return value


def draw_trace(ax, events, y, xlim, color, amplitude=0.67):
    # 阶梯形波形，补齐视窗左右边界以便读数。
    x0, x1 = xlim
    points = [(x0, value_at(events, x0))]
    points += [(t, v) for t, v in events if x0 < t < x1]
    points.append((x1, value_at(events, x1)))
    xs = [t for t, _ in points]
    ys = [y + min(v, 1) * amplitude for _, v in points]
    ax.step(xs, ys, where="post", color=color, lw=1.5)


def panel(ax, traces, xlim, title):
    colors = ["#66d9ef", "#f7bf4f", "#a4e28c", "#e58fb4", "#c3a6ff", "#f5796f"]
    for index, (label, events) in enumerate(traces):
        y = len(traces) - index - 1
        draw_trace(ax, events, y, xlim, colors[index % len(colors)])
    ax.set_yticks([len(traces) - index - 1 + 0.3 for index in range(len(traces))])
    ax.set_yticklabels([label for label, _ in traces])
    ax.set_ylim(-0.2, len(traces))
    ax.set_xlim(*xlim)
    ax.grid(axis="x", color="#354557", alpha=0.75)
    ax.set_title(title, loc="left", color="white", fontsize=13)
    ax.set_xlabel("时间 / ms")


def main():
    data = read_vcd(VCD)
    p = "tb_acg720_nav_preview"
    get = lambda name: data[f"{p}/{name}"]
    # 总览的三组 UART 帧依次是：合法示例、坏 CRC、障碍内终点。
    overview = [
        ("UART RX", get("uart_rx")),
        ("至少收到 1 个合法终点", [(t, min(v, 1)) for t, v in get("goal_pulses")]),
        ("搜索 busy", get("dut/planner_busy")),
        ("路径 ready", get("dut/route_ready")),
        ("不可达 no_path", get("dut/no_path")),
        ("LED7 错误", get("led[5]")),
    ]
    first_goal_ms = next(t for t, v in get("goal_pulses") if v == 1)
    detail = [
        ("已收合法终点", [(t, int(v >= 1)) for t, v in get("goal_pulses")]),
        ("BFS busy", get("dut/planner_busy")),
        ("路径 ready", get("dut/route_ready")),
        ("LED6 找到路线", get("led[4]")),
        ("步数=34", [(t, int(v == 34)) for t, v in get("dut/u_planner/path_steps_o[8:0]")]),
    ]
    plt.rcParams.update({"font.family": "SimHei", "axes.unicode_minus": False,
                         "figure.facecolor": "#101a29", "axes.facecolor": "#152235",
                         "axes.labelcolor": "white", "xtick.color": "white",
                         "ytick.color": "white", "text.color": "white"})
    fig, axes = plt.subplots(2, 1, figsize=(15, 8), layout="constrained")
    panel(axes[0], overview, (0, 3.85), "ModelSim 集成仿真总览：正确帧 → CRC 错帧 → 障碍内目标")
    panel(axes[1], detail, (first_goal_ms - 0.01, first_goal_ms + 0.09),
          "首个合法终点的规划细节（FPGA 自行搜索，输出 34 步）")
    fig.savefig(PNG, dpi=160)
    print(PNG)


if __name__ == "__main__":
    main()
