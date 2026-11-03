from pathlib import Path
import ast,hashlib,json,xml.etree.ElementTree as E
r=Path(__file__).resolve().parents[1]
m=json.loads((r/'PACKAGE_SHA256.json').read_text(encoding='utf-8'))
for rel,h in m.items():
 p=r/rel
 assert p.is_file(),rel
 assert hashlib.sha256(p.read_bytes()).hexdigest()==h,rel
p=r/'fpga/sin12_hdmi/sin12_hdmi_system.gprj'
for item in E.parse(p).findall('.//File'):assert (p.parent/item.attrib['path']).resolve().is_file(),item.attrib['path']
files=list(r.rglob('*.py'))
for p in files:ast.parse(p.read_bytes(),filename=str(p))
print('PASS:',len(m),'SHA256 files;',len(files),'Python sources; all FPGA project dependencies present. No hardware access.')
