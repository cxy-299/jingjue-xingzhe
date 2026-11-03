"""Printable physical SIN12 map, with no planning grid or inflated cells."""
from pathlib import Path
import json
import re
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.units import mm
from reportlab.lib.pagesizes import A4
from pypdf import PdfReader

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=ROOT/'output/pdf/SIN12_map_2613_print_no_grid.pdf'

def draw_map(pdf,spec,x,y,side,full=False):
    cell=side/spec['grid_cells']
    for obstacle in spec['obstacles']:
        ox,oy=obstacle['min_cell'];w,h=obstacle['size_cells']
        pdf.setFillColorRGB(.83,.83,.83)
        pdf.setStrokeColorRGB(0,0,0)
        pdf.setLineWidth(.7 if not full else 2)
        pdf.rect(x+ox*cell,y+oy*cell,w*cell,h*cell,stroke=1,fill=1)
        size=8 if not full else 36
        pdf.setFillColorRGB(0,0,0);pdf.setFont('Helvetica-Bold',size)
        pdf.drawCentredString(x+(ox+w/2)*cell,y+(oy+h/2)*cell-size*.34,obstacle['id'])
    sx,sy=spec['start_cell'];cx=x+(sx+.5)*cell;cy=y+(sy+.5)*cell
    radius=3.2*mm if not full else 30*mm
    pdf.setFillColorRGB(1,1,1);pdf.setStrokeColorRGB(0,0,0)
    pdf.circle(cx,cy,radius,stroke=1,fill=1)
    size=7 if not full else 32
    pdf.setFillColorRGB(0,0,0);pdf.setFont('SimHei',size)
    pdf.drawCentredString(cx,cy-size*.34,'起点')
    pdf.setLineWidth(.8 if not full else 2)
    pdf.rect(x,y,side,side,stroke=1,fill=0)

def main():
    spec=json.loads((ROOT/'config/nav-map-sin12.json').read_text(encoding='utf-8'))
    # Verify the JSON matches the actual compiled occupancy map before printing.
    from scripts.build_nav_map import occupied_cells
    header=(ROOT/'fpga/nav/sin12_map.vh').read_text()
    bits=sum(v<<i for i,v in enumerate(occupied_cells(spec)))
    assert spec['map_id']==int(re.search(r"MAP_ID 16'h([0-9a-fA-F]+)",header)[1],16)
    assert bits==int(re.search(r"MAP_BITS 400'h([0-9a-fA-F]+)",header)[1],16)
    assert spec['size_m']==2 and spec['origin']=='bottom_left'
    pdfmetrics.registerFont(TTFont('SimHei','C:/Windows/Fonts/simhei.ttf'))
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    pdf=canvas.Canvas(str(OUTPUT),pagesize=A4,pageCompression=1)
    pdf.setTitle('SIN12 0x2613 - 起点与实体障碍物打印地图')
    pdf.setAuthor('灵枢视觉导航项目')
    pdf.setFont('SimHei',15);pdf.drawCentredString(A4[0]/2,265*mm,'2米 × 2米 实测场地地图')
    pdf.setFont('SimHei',9);pdf.drawCentredString(A4[0]/2,255*mm,'SIN12 / 地图 0x2613 / A4缩尺图 1:12')
    side=2000*mm/12;x=(A4[0]-side)/2;y=65*mm
    draw_map(pdf,spec,x,y,side)
    pdf.setFont('SimHei',9)
    pdf.drawCentredString(A4[0]/2,49*mm,'灰色矩形为实体障碍物；起点为车体中心，车头朝图上方。')
    pdf.drawCentredString(A4[0]/2,41*mm,'本页为缩尺参考；第2页为2000 × 2000 mm原尺寸地图。')
    pdf.drawCentredString(A4[0]/2,33*mm,'原尺寸打印：选第2页、100%实际大小；普通打印机可用“海报”拼接。')
    pdf.showPage()
    pdf.setPageSize((2000*mm,2000*mm))
    draw_map(pdf,spec,0,0,2000*mm,full=True)
    pdf.showPage();pdf.save()
    doc=PdfReader(OUTPUT);assert len(doc.pages)==2
    assert abs(float(doc.pages[1].mediabox.width)/mm-2000)<.01
    assert abs(float(doc.pages[1].mediabox.height)/mm-2000)<.01
    assert '起点' in doc.pages[1].extract_text()
    print(OUTPUT)

if __name__=='__main__':main()
