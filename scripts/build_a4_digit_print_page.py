"""Generate an offline browser-printable 0..9 A4 target set (not a PDF).
All glyphs are rasterised once using the recorded source font; no OCR engine or
font installation is required on the Pi. Physical print scale remains operator checked.
"""
import argparse
import base64
import hashlib
import io
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

def target_image(number,font_path):
    image=Image.new('RGB',(1260,1782),'white') # 6px/mm, exact A4 ratio
    draw=ImageDraw.Draw(image);font=ImageFont.truetype(str(font_path),900)
    for x in (60,1140):draw.rectangle((x,60,x+60,120),fill='black')
    text=str(number);b=draw.textbbox((0,0),text,font=font)
    draw.text(((1260-b[2]+b[0])/2-b[0],(1782-b[3]+b[1])/2-b[1]),text,fill='black',font=font)
    return image

def build(font_path):
    cards=[]
    for n in range(10):
        stream=io.BytesIO();target_image(n,font_path).save(stream,format='PNG')
        uri=base64.b64encode(stream.getvalue()).decode()
        cards.append(f'<section class="sheet" data-digit="{n}"><img alt="A4 digit {n}" src="data:image/png;base64,{uri}"></section>')
    return '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>A4数字靶纸0–9</title>
<style>@page{size:A4 portrait;margin:0}*{box-sizing:border-box}body{font:16px sans-serif;margin:0;background:#ddd}
header{padding:20px}.sheet{width:210mm;height:297mm;background:white;margin:20px auto;break-after:page}
.sheet img{display:block;width:210mm;height:297mm}button,select{font-size:18px;padding:8px}
@media screen{.sheet{width:315px;height:445.5px}.sheet img{width:315px;height:445.5px}}
@media print{header{display:none}body{background:white}.sheet{margin:0;page-break-after:always}.sheet:last-child{page-break-after:auto}.skip{display:none!important}}</style>
<header><h1>A4数字靶纸0–9</h1><p>竖向A4，实际大小100%，不缩放，关闭页眉页脚。顶部两个黑方块必须保留，禁止倒置。打印后量纸张210×297mm，平整固定，不弯折，数字完整入镜。空白纸/多位数/手写数字不属本版范围。</p>
<select id="digit">'''+''.join(f'<option value="{n}">{n}</option>' for n in range(10))+'''</select>
<button onclick="printCards(false)">打印所选数字（一张）</button><button onclick="printCards(true)">打印全部数字（十张）</button>
<p>这是尺寸约定的打印靶纸，不是相机/ToF标定结果；打印不会发送任何任务或运动命令。</p></header>
'''+''.join(cards)+'''<script>
function restore(){document.querySelectorAll('.sheet').forEach(s=>s.classList.remove('skip'));}
function printCards(all){const selected=document.getElementById('digit').value;document.querySelectorAll('.sheet').forEach(s=>s.classList.toggle('skip',!all&&s.dataset.digit!==selected));window.print();}
window.addEventListener('afterprint',restore);
</script></html>'''+f'<!-- Source font {Path(font_path).name} SHA256 {hashlib.sha256(Path(font_path).read_bytes()).hexdigest()} -->'

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--font',type=Path,required=True)
    ap.add_argument('--out',type=Path,default=Path('web/a4-targets.html'))
    args=ap.parse_args();args.out.write_text(build(args.font),encoding='utf8')

