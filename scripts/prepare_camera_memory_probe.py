"""Reproducible isolated camera synthesis: explicitly avoid unsupported SSRAM inference."""
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tmp/ov5640_hdmi_src_20261026'
DEST = ROOT / 'tmp/ov5640_memory_probe'


def main():
    project = ET.parse(SOURCE/'ov5640_ddr3_hdmi.gprj')
    for entry in project.findall('.//File'):
        relative = Path(entry.attrib['path'])
        target = DEST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE/relative, target)
    # PLL_INIT and dynamic PLL source wrappers have relative includes.
    for relative in ('src/pll_init.v','src/pll_mDRP_intf.v'):
        if (SOURCE/relative).exists():
            shutil.copy2(SOURCE/relative, DEST/relative)
    gsc = DEST/'src/memory_implementation.gsc'
    gsc.write_text('GLOBAL syn_ramstyle = block_ram\nGLOBAL syn_romstyle = logic\nGLOBAL syn_srlstyle = registers\n',encoding='ascii')
    ET.SubElement(project.find('.//FileList'),'File',path='src/memory_implementation.gsc',type='file.gsc',enable='1')
    project.write(DEST/'ov5640_memory_probe.gprj',encoding='utf-8',xml_declaration=True)
    (DEST/'build_camera_probe.tcl').write_text(f'''cd {DEST.as_posix()}
open_project {(DEST/'ov5640_memory_probe.gprj').as_posix()}
set_option -top_module gao_ov5640_ddr_hdmi
set_option -user_code 43414D50
run syn
''',encoding='utf-8')
    print(DEST/'build_camera_probe.tcl')


if __name__ == '__main__':
    main()
