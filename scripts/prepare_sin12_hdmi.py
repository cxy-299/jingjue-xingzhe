"""Build SIN12 R5 candidate: camera, feedback startup, recovery and local avoidance."""
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'fpga/sin12_hdmi'
CAMERA=ROOT/'tmp/ov5640_case_rom_probe'


def main():
    copied=[]
    for folder in ('src/camera_init','src/camera_pll'):
        for source in (CAMERA/folder).rglob('*.v'):
            rel=source.relative_to(CAMERA)
            target=DEST/'camera_vendor'/rel
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target);copied.append(target)
    for rel in ('src/pll_init.v',):
        target=DEST/'camera_vendor'/rel;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(CAMERA/rel,target);copied.append(target)
    # Keep the vendor's pixel-rate TMDS encoder, but replace its fabric 5x
    # shift-register serializer (failed 375 MHz setup and pixel->serial hold)
    # with the native Arora V OSER10 IOLOGIC implemented in our own source.
    vendor_dvi=(CAMERA/'src/vga/dvi_encoder.v').read_text(encoding='utf-8')
    encode=vendor_dvi[vendor_dvi.index('module encode('):vendor_dvi.index('module serdes_4b_10to1(')]
    target=DEST/'camera_vendor/src/vga/tmds_encode.v'
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text('`timescale 1ps/1ps\n`define D #1\n'+encode,encoding='utf-8');copied.append(target)
    original=ET.parse(ROOT/'fpga/motor_bt_drive/acg720_motor_bt_autonav.gprj')
    project=ET.Element('Project')
    for name,value in [('Template','FPGA'),('Version','5')]: ET.SubElement(project,name).text=value
    project.append(original.find('Device'));listing=ET.SubElement(project,'FileList')
    for entry in original.findall('.//File'):
        if entry.attrib['type'] in ('file.cst','file.sdc'):continue
        path=(ROOT/'fpga/motor_bt_drive'/entry.attrib['path']).resolve()
        ET.SubElement(listing,'File',path=path.as_posix(),type=entry.attrib['type'],enable='1')
    for path in copied+[DEST/'sin12_video_startup.v',DEST/'sin12_dvi_encoder.v',DEST/'sin12_camera_hdmi.v',DEST/'sin12_hdmi_system.v']:
        ET.SubElement(listing,'File',path=path.as_posix(),type='file.verilog',enable='1')
    motor_cst=(ROOT/'fpga/motor_bt_drive/acg720_motor_bt_autonav.cst').read_text(encoding='utf-8')
    camera_cst=(CAMERA/'src/ov5640_ddr3_hdmi.cst').read_text(encoding='utf-8')
    camera_lines=[line for line in camera_cst.splitlines() if re.match(r'IO_(LOC|PORT) "(?:camera_|tmds_)',line)]
    # UG304 3.6.6: one ELVDS_OBUF per native OSER10, complementary LVCMOS
    # output pair. ACG720 sheet 8 has 49.9-ohm pull-ups to 3.3 V; keep
    # voltage/drive and pin polarity, use the differential LVCMOS33D form.
    camera_lines=[line.replace('IO_TYPE=LVCMOS33 ', 'IO_TYPE=LVCMOS33D ')
                  if line.startswith('IO_PORT "tmds_') else line for line in camera_lines]
    cst=motor_cst+'\n// Camera/HDMI dedicated pins from tested vendor example.\n'+'\n'.join(camera_lines)+'\n'
    # SUG1541 2.8: use a global clock line instead of PR1014 generic PCLK
    # routing. The net name is taken from the previous synthesized netlist.
    cst+='CLOCK_LOC "camera_pclk_d" BUFG = CLK;\n'
    pins={}
    for port,pin in re.findall(r'IO_LOC "([^"]+)" ([A-Z]+\d+);',cst):
        assert pin not in pins, f'Pin collision {pin}: {pins.get(pin)} and {port}'
        pins[pin]=port
    (DEST/'sin12_hdmi_system.cst').write_text(cst,encoding='utf-8')
    sdc='''create_clock -name clk_50m -period 20.000 [get_ports {clk_50m_i}]
create_clock -name camera_pclk -period 13.333 [get_ports {camera_pclk}]
create_generated_clock -name camera_serial_raw -source [get_ports {clk_50m_i}] -multiply_by 15 -divide_by 2 [get_pins {u_camera/u_pll/u_pll_0/PLLA_inst/CLKOUT0}]
# DHCE is a clock boundary in this tool. Explicitly propagate the 375 MHz
# clock to its output instead of leaving the OSER10 FCLK unclocked.
create_generated_clock -name camera_serial -source [get_pins {u_camera/u_pll/u_pll_0/PLLA_inst/CLKOUT0}] -divide_by 1 [get_pins {u_camera/u_startup/u_serial_gate/CLKOUT}]
create_generated_clock -name camera_pixel -source [get_pins {u_camera/u_startup/u_serial_gate/CLKOUT}] -divide_by 5 [get_pins {u_camera/u_pixel_div/CLKOUT}]
create_generated_clock -name camera_xclk -source [get_ports {clk_50m_i}] -divide_by 2 [get_pins {u_camera/u_pll/u_pll_0/PLLA_inst/CLKOUT1}]
set_clock_groups -asynchronous -group [get_clocks {camera_pclk}] -group [get_clocks {clk_50m camera_serial_raw camera_serial camera_pixel camera_xclk}]
# DHCE holds FCLK/PCLK stopped for >=160 ns after RESET release. Budget only
# 16 FCLK cycles (~42 ns) for the startup-only RESET route, well inside the
# proven quiet window. These endpoints remain timed (no false path). No
# pixel data path, running clock period, or car-control path is relaxed.
set_multicycle_path -through [get_pins {OSER_RESET_PINS}] -to [get_clocks {camera_serial}] -setup -end 16
set_multicycle_path -through [get_pins {OSER_RESET_PINS}] -to [get_clocks {camera_serial}] -hold -end 15
# DHCE's active-low CEN is an asynchronous control input, with four falling-
# edge synchronization stages in the official primitive. Exempt that first
# asynchronous sampling endpoint only, not any data/RESET/clock path.
set_false_path -to [get_pins {u_camera/u_startup/u_serial_gate/CEN}]
report_timing -recovery -to [get_pins {OSER_RESET_PINS}] -max_paths 24 -max_common_paths 3
report_timing -removal -to [get_pins {OSER_RESET_PINS}] -max_paths 24 -max_common_paths 3
report_min_pulse_width -nworst 100 -detail
report_timing -recovery -max_paths 200 -max_common_paths 3
report_timing -removal -max_paths 200 -max_common_paths 3
# Only the two pixel reset synchronizer asynchronous CLEAR inputs.
set_false_path -to [get_pins {u_camera/pixel_release_meta*/CLEAR u_camera/pixel_release_sync*/CLEAR}]
'''
    sdc=sdc.replace('OSER_RESET_PINS',' '.join(
        f'u_camera/u_dvi/g_channel[{i}].u_serial/u_serializer/RESET' for i in range(4)))
    (DEST/'sin12_hdmi_system.sdc').write_text(sdc,encoding='ascii')
    for path,kind in [('sin12_hdmi_system.cst','file.cst'),('sin12_hdmi_system.sdc','file.sdc')]:
        ET.SubElement(listing,'File',path=path,type=kind,enable='1')
    ET.ElementTree(project).write(DEST/'sin12_hdmi_system.gprj',encoding='utf-8',xml_declaration=True)
    (DEST/'build_sin12_hdmi.tcl').write_text(f'''cd {DEST.as_posix()}
open_project {(DEST/'sin12_hdmi_system.gprj').as_posix()}
set_option -top_module sin12_hdmi_system
set_option -user_code 534E3247
set_option -route_option 2
set_option -timing_driven 1
set_option -use_sspi_as_gpio 1
run all
''',encoding='utf-8')
    print(f'Prepared SIN12 R7 HDMI; {len(pins)} unique pins; user code 0x534E3247, map0x2613')


if __name__=='__main__':main()
