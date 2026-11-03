"""Render the same WXML/WXSS with a small DOM adapter, for layout QA only.

This is not the WeChat compiler or a substitute for DevTools/physical-phone tests.
No real network transport is provided by this preview.
"""
import json
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
MINI=ROOT/'miniprogram'
css=(MINI/'app.wxss').read_text('utf-8')+'\n'+(MINI/'pages/index/index.wxss').read_text('utf-8')
css=re.sub(r'(?<![\w-])page\b','body',css)
css=re.sub(r'([\d.]+)rpx',r'calc(100vw * \1 / 750)',css)
modules={}
for file in (MINI/'lib').glob('*.js'):modules['lib/'+file.stem]=file.read_text('utf-8')
modules['pages/index/index']=(MINI/'pages/index/index.js').read_text('utf-8')
wxml=(MINI/'pages/index/index.wxml').read_text('utf-8').replace('wx:','wx-')
wxml=re.sub(r'\bwx-else(?=[\s>])','wx-else=""',wxml)
adapter=(ROOT/'qa/preview_adapter.js').read_text('utf-8')
html='''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>境觉行者 · 原生小程序布局预览</title><style>html,body{margin:0}*{box-sizing:border-box}input{width:100%;font:inherit}button{font-family:inherit}#toast{position:fixed;top:40%;left:10%;right:10%;padding:20px;background:#253b48;z-index:99;border-radius:14px;text-align:center}.detection-row{width:100%;margin:8px 0;text-align:left}'''+css+'''</style></head><body><div id="app"></div><div id="toast" hidden></div><script>window.MODULES='''+json.dumps(modules,ensure_ascii=False)+''';window.WXML='''+json.dumps(wxml,ensure_ascii=False)+''';</script><script>'''+adapter+'''</script></body></html>'''
(ROOT/'qa/preview.html').write_text(html,'utf-8')
print('Built WXML/WXSS layout preview (demo only)')
