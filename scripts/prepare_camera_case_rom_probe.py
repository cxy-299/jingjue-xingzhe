"""Isolate OV5640 SCCB ROM inference from encrypted DDR/FIFO IP problems."""
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tmp/ov5640_memory_probe'
DEST = ROOT / 'tmp/ov5640_case_rom_probe'


def main():
    project = ET.parse(SOURCE / 'ov5640_memory_probe.gprj')
    for entry in project.findall('.//File'):
        rel = Path(entry.attrib['path'])
        (DEST / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / rel, DEST / rel)
    for rel in ('src/pll_init.v', 'src/pll_mDRP_intf.v'):
        if (SOURCE / rel).exists():
            shutil.copy2(SOURCE / rel, DEST / rel)
    rom = DEST / 'src/camera_init/ov5640_init_table_rgb.v'
    source = rom.read_text(encoding='utf-8')
    header = source[:source.index('  // Declare the ROM variable')]
    entries = re.findall(r'rom\[\s*(\d+)\s*\]\s*=\s*([^;]+);', source)
    assert len(entries) == 253 and {int(i) for i, _ in entries} == set(range(253))
    case = ['  // Explicit logic mux: no distributed ROM/SSRAM inference.',
            '  always @(posedge clk) begin', '    case (addr)']
    case += [f"      8'd{int(i)}: q <= {value.strip()};" for i, value in entries]
    case += ["      default: q <= 24'd0;", '    endcase', '  end', 'endmodule', '']
    rom.write_text(header + '\n'.join(case), encoding='utf-8')
    project.write(DEST / 'ov5640_case_rom_probe.gprj', encoding='utf-8', xml_declaration=True)
    (DEST / 'build_case_rom.tcl').write_text(f'''cd {DEST.as_posix()}
open_project {(DEST/'ov5640_case_rom_probe.gprj').as_posix()}
set_option -top_module gao_ov5640_ddr_hdmi
set_option -user_code 434D4350
run syn
''', encoding='utf-8')
    print(DEST / 'build_case_rom.tcl')


if __name__ == '__main__':
    main()
