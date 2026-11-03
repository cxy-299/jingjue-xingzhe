"""Build portable glyph bitmaps; no font files are redistributed.
Runtime only needs OpenCV+NumPy. Source fonts and hashes are recorded.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import zlib
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from src.detection.a4_digit import normalize_glyph

def build(fonts):
    samples=[];sources=[]
    for path in fonts:
        path=Path(path)
        sources.append(dict(name=path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        for n in range(10):
            font=ImageFont.truetype(str(path),220)
            image=Image.new('L',(320,340),0)
            draw=ImageDraw.Draw(image)
            box=draw.textbbox((0,0),str(n),font=font)
            draw.text(((320-box[2]+box[0])/2-box[0],(340-box[3]+box[1])/2-box[1]),str(n),fill=255,font=font)
            original=np.array(image)
            for size in (48,80,180):
                reduced=cv2.resize(original,(size,size),interpolation=cv2.INTER_AREA)
                _,binary=cv2.threshold(reduced,100,255,cv2.THRESH_BINARY)
                glyph=normalize_glyph(binary)
                samples.append(dict(digit=n,font=path.name,render_size=size,
                    pixels=base64.b64encode(zlib.compress(glyph.tobytes(),9)).decode()))
    return dict(schema=1,shape=[48,36],method='normalised printed glyph correlation; not a trained object detector',fonts=sources,samples=samples)

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--font',action='append',required=True)
    ap.add_argument('--out',type=Path,default=Path('assets/a4_digits_templates.json'))
    args=ap.parse_args();args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(build(args.font),indent=2)+'\n',encoding='utf8')

