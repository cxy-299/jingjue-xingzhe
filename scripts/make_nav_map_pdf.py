"""生成赛题三固定地图：A3 尺寸图 + 2 m 实际尺寸地贴图。"""

from __future__ import annotations

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A3, landscape
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from build_nav_map import ROOT, load_map, occupied_cells, shortest_path


OUTPUT = ROOT / "output" / "pdf" / "topic3_fixed_map_2m_v4_balanced.pdf"
FONT_FILE = Path("C:/Windows/Fonts/simhei.ttf")


def c(hex_color: str):
    return colors.HexColor(hex_color)


def text(pdf, x, y, content, size=9, color="#17324c", font="SimHei"):
    pdf.setFont(font, size)
    pdf.setFillColor(c(color))
    pdf.drawString(x, y, content)


def draw_map(pdf, x0, y0, side, spec, occupied, route=(), labels=True, full_size=False):
    n = spec["grid_cells"]
    cell = side / n
    pdf.setFillColor(c("#f7fbff"))
    pdf.rect(x0, y0, side, side, stroke=0, fill=1)

    # 灰区是车体中心不可进入的安全膨胀区，红色才是实际摆放障碍的位置。
    for row in range(n):
        for col in range(n):
            if occupied[row * n + col]:
                pdf.setFillColor(c("#dce4e9"))
                pdf.rect(x0 + col * cell, y0 + row * cell, cell, cell, stroke=0, fill=1)
    for obstacle in spec["obstacles"]:
        ox, oy = obstacle["min_cell"]
        w, h = obstacle["size_cells"]
        pdf.setFillColor(c("#df665a"))
        pdf.rect(x0 + ox * cell, y0 + oy * cell, w * cell, h * cell, stroke=0, fill=1)
        pdf.setFont("SimHei", 75 if full_size else 10)
        pdf.setFillColor(colors.white)
        pdf.drawCentredString(x0 + (ox + w / 2) * cell, y0 + (oy + h / 2) * cell - (26 if full_size else 3), obstacle["id"])

    pdf.setLineWidth(0.35 if full_size else 0.25)
    for i in range(n + 1):
        pdf.setStrokeColor(c("#b6c7d3") if i % 5 else c("#6b8aa0"))
        pdf.setLineWidth((1.4 if full_size else 0.65) if i % 5 == 0 else (0.65 if full_size else 0.25))
        pdf.line(x0 + i * cell, y0, x0 + i * cell, y0 + side)
        pdf.line(x0, y0 + i * cell, x0 + side, y0 + i * cell)

    if route:
        route_path = pdf.beginPath()
        for i, (col, row) in enumerate(route):
            px, py = x0 + (col + 0.5) * cell, y0 + (row + 0.5) * cell
            if i == 0:
                route_path.moveTo(px, py)
            else:
                route_path.lineTo(px, py)
        pdf.setStrokeColor(c("#188ce0"))
        pdf.setLineWidth(2.5)
        pdf.drawPath(route_path)

    def marker(col, row, fill, label):
        px, py = x0 + (col + 0.5) * cell, y0 + (row + 0.5) * cell
        pdf.setFillColor(c(fill))
        pdf.circle(px, py, 90 if full_size else 5.5, stroke=0, fill=1)
        pdf.setFont("SimHei", 65 if full_size else 7)
        pdf.setFillColor(colors.white)
        pdf.drawCentredString(px, py - (23 if full_size else 2.3), label)

    marker(*spec["start_cell"], "#138a66", "起")
    if route:
        marker(*spec["example_goal_cell"], "#e59d24", "终")

    pdf.setStrokeColor(c("#164362"))
    pdf.setLineWidth(2 if full_size else 1)
    pdf.rect(x0, y0, side, side, stroke=1, fill=0)
    if labels:
        for i in (0, 5, 10, 15, 20):
            text(pdf, x0 + i * cell - 4, y0 - 5 * mm, f"{i / 10:g}", 8)
            text(pdf, x0 - 9 * mm, y0 + i * cell - 2, f"{i / 10:g}", 8)


def draw_blueprint(pdf, spec, occupied, route):
    page_w, page_h = landscape(A3)
    pdf.setPageSize((page_w, page_h))
    pdf.setFillColor(c("#eef4f8"))
    pdf.rect(0, 0, page_w, page_h, stroke=0, fill=1)
    text(pdf, 20 * mm, 282 * mm, "赛题三 · 2 m × 2 m 固定障碍地图", 18)
    text(pdf, 20 * mm, 275 * mm, "A3 布置图 / 比例 1:8 / GUI 地图 v4-balanced / 地图 ID 0x2601", 9, "#476177")
    x0, y0, side = 20 * mm, 20 * mm, 250 * mm
    draw_map(pdf, x0, y0, side, spec, occupied, route, labels=True)

    px = 282 * mm
    text(pdf, px, 256 * mm, "实际尺寸和坐标", 12)
    lines = [
        "地图：200 × 200 cm；20 × 20 格",
        "每格：10 × 10 cm（图上 12.5 mm）",
        "原点：左下；X 向右，Y 向上",
        "起点：车体中心 (185, 15) cm，朝 +Y",
        "示例终点：(25, 175) cm（可由 GUI 改）",
        "示例路线：32 步，中心线约 3.2 m",
    ]
    for i, line in enumerate(lines):
        text(pdf, px, (246 - 8 * i) * mm, line, 8.2)

    text(pdf, px, 188 * mm, "实体障碍位置（左下角坐标）", 11)
    for i, obstacle in enumerate(spec["obstacles"]):
        x, y = obstacle["min_cell"]
        w, h = obstacle["size_cells"]
        text(pdf, px, (178 - 9 * i) * mm,
             f"{obstacle['id']}  ({x * 10}, {y * 10}) cm，{w * 10} × {h * 10} cm", 8.5)

    text(pdf, px, 132 * mm, "颜色说明", 11)
    legend = [("#df665a", "实际障碍实体"), ("#dce4e9", "中心不可进入安全区"),
              ("#188ce0", "示例最短路线"), ("#138a66", "固定起点"), ("#e59d24", "示例终点")]
    for i, (color, label) in enumerate(legend):
        yy = (122 - 9 * i) * mm
        pdf.setFillColor(c(color))
        pdf.rect(px, yy - 2 * mm, 5 * mm, 5 * mm, stroke=0, fill=1)
        text(pdf, px + 8 * mm, yy, label, 8.2)

    text(pdf, px, 68 * mm, "安装与使用", 11)
    notes = [
        "1. A3 页是缩尺图，不可作 1:1 地贴。",
        "2. 第 2 页为 2000 × 2000 mm 真尺寸。",
        "3. 障碍按红色足迹放置，不超出矩形。",
        "4. 车宽暂按 20 cm，另留 5 cm 余量。",
        "5. 起点朝向、轮径/编码器需实测标定。",
        "6. 未接定位/ToF 前禁止实车自主行驶。",
    ]
    for i, line in enumerate(notes):
        text(pdf, px, (59 - 7 * i) * mm, line, 7.6, "#355168")
    text(pdf, 20 * mm, 8 * mm, "地图版本 v4-balanced · FPGA 片上地图数据由同一 JSON 生成 · 请按 100% 比例打印第 2 页", 8, "#476177")
    pdf.showPage()


def draw_full_size(pdf, spec, occupied):
    side = 2000 * mm
    pdf.setPageSize((side, side))
    draw_map(pdf, 0, 0, side, spec, occupied, route=(), labels=False, full_size=True)
    pdf.showPage()


def main():
    if not FONT_FILE.exists():
        raise FileNotFoundError(f"缺少中文字体：{FONT_FILE}")
    pdfmetrics.registerFont(TTFont("SimHei", str(FONT_FILE)))
    spec = load_map()
    occupied = occupied_cells(spec)
    route = shortest_path(spec, occupied, tuple(spec["example_goal_cell"]))
    if not route:
        raise RuntimeError("示例终点不可达，请检查地图障碍与膨胀参数")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(OUTPUT), pagesize=landscape(A3), pageCompression=1)
    pdf.setTitle("赛题三 2×2 米固定障碍地图 v1")
    pdf.setAuthor("灵枢视觉导航项目")
    draw_blueprint(pdf, spec, occupied, route)
    draw_full_size(pdf, spec, occupied)
    pdf.save()
    print(OUTPUT)


if __name__ == "__main__":
    main()
