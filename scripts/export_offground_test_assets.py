"""Export blank result CSV and an auditable old/new geometry comparison PNG."""
import csv
import json
import re
import zipfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from scripts.build_nav_map import occupied_cells, shortest_path_from

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / 'output/board'


def main():
    checklist = BOARD / 'TASK1_6_OFFGROUND_CHECKLIST_2026-10-27.md'
    rows = []
    for line in checklist.read_text(encoding='utf-8').splitlines():
        if not re.match(r'^\| [A-F]\d\d', line):
            continue
        parts = [part.strip() for part in line.strip('|').split('|')]
        rows.append([parts[0], parts[1], parts[2], '', '', '', '', ''])
    with (BOARD / 'TASK1_6_OFFGROUND_RESULTS_2026-10-27.csv').open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['项目ID', '操作', '预期结果', '实际结果', '通过/失败/未测/待落地', '日志时间/任务号', '首次F/W/E/X/P', '备注'])
        writer.writerows(rows)

    with zipfile.ZipFile(BOARD / 'sin12_before_sparse_map_2026-10-27.zip') as archive:
        old = json.loads(archive.read('nav-map-sin12.json').decode('utf-8'))
    new = json.loads((ROOT / 'config/nav-map-sin12.json').read_text(encoding='utf-8'))
    font_file = Path('C:/Windows/Fonts/msyh.ttc')
    font = ImageFont.truetype(str(font_file), 23)
    small = ImageFont.truetype(str(font_file), 17)
    image = Image.new('RGB', (1260, 750), '#08131f')
    draw = ImageDraw.Draw(image)
    draw.text((25, 12), '四个障碍保留原位，车体200×220mm、膨胀210mm保持不变', font=font, fill='white')
    for panel, (name, spec) in enumerate((('旧版 0x2612', old), ('新版 0x2613', new))):
        x0, y0, cell = 30 + panel*625, 100, 27
        cells = occupied_cells(spec)
        fixed = {(x, y) for o in spec['obstacles'] for y in range(o['min_cell'][1], o['min_cell'][1]+o['size_cells'][1])
                 for x in range(o['min_cell'][0], o['min_cell'][0]+o['size_cells'][0])}
        reachable = {(x, y) for y in range(20) for x in range(20)
                     if shortest_path_from(spec, cells, tuple(spec['start_cell']), (x, y))}
        draw.text((x0, 60), f'{name}：起点连通 {len(reachable)} 格', font=font, fill='#91d9ff')
        for y in range(20):
            for x in range(20):
                left, top = x0+x*cell, y0+(19-y)*cell
                color = '#ed7864' if (x,y) in fixed else '#54464c' if cells[y*20+x] else '#184358' if (x,y) in reachable else '#6a5a25'
                draw.rectangle((left, top, left+cell, top+cell), fill=color, outline='#29465a')
        sx, sy = spec['start_cell']
        draw.ellipse((x0+sx*cell+3,y0+(19-sy)*cell+3,x0+(sx+1)*cell-3,y0+(20-sy)*cell-3),fill='#48d6a3')
        draw.text((x0, 650), '绿色：起点(17,2)；蓝色：与起点连通的格', font=small, fill='white')
        draw.text((x0, 679), '橙色：实体障碍；灰色：含外廓/余量的禁行区', font=small, fill='white')
    draw.text((30, 718), '每格10cm；褐黄色为不连通空格。布局计算不代替实车通行/定位验收。', font=small, fill='#d3dbe5')
    target = BOARD / 'sin12_map2613_comparison.png'
    image.save(target)
    print(f'{len(rows)} blank result rows; map comparison: {target}')


if __name__ == '__main__':
    main()
