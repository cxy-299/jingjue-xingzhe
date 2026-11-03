"""Generate versioned verification scaffolding; no reuse of prior PASS evidence."""
import hashlib
import json
from pathlib import Path
from src.comm.autonav import pack_autonav_goal

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board'


def main():
    # Mechanically adapt evidence readers. All runtime assertions still inspect
    # the NEW netlist; original-name assumptions must be reviewed on actual VG.
    scripts=['build_sin12_r17.ps1','inspect_sin12_r17_timing.py','audit_sin12_r17_constraints.py',
             'verify_sin12_r17_mapped_tof.py','verify_sin12_r17_mapped_target.py',
             'verify_sin12_r17_mapped_nav.py']
    for name in scripts:
        text=(ROOT/'scripts'/name).read_text(encoding='utf8')
        text=text.replace('r17','r18').replace('R17','R18').replace('534E3251','534E3252')
        target=ROOT/'scripts'/name.replace('r17','r18')
        assert not target.exists(),'Inspect existing generated file before replacing'
        target.write_text(text,encoding='utf8')
    full=(ROOT/'fpga/motor_bt_drive/tb_sin12_r17_full.sv').read_text()
    full=full.replace('r17','r18').replace('CONTROL_REV=13','CONTROL_REV=14')
    full=full.replace('CELL_COUNTS!=333','CELL_COUNTS!=500')
    full=full.replace('"sin12_r16_packet_frames.mem"','"sin12_r18_packet_frames.mem"')
    full=full.replace('"old 1000-count packet accepted by R16"','"old 333-count packet accepted by R18"')
    full=full.replace('R16','R18')
    full=full.replace('if(dut.g_navigation.u_nav_route.PROGRESS_PIPELINE!=1)',
                      'if(dut.g_autonav.u_guard.FIXED_LEFT_DETOUR!=1) $fatal(1,"R18 detour disabled");\n        if(dut.g_navigation.u_nav_route.PROGRESS_PIPELINE!=1)')
    (ROOT/'fpga/motor_bt_drive/tb_sin12_r18_full.sv').write_text(full)
    run=(ROOT/'fpga/motor_bt_drive/run_modelsim_sin12_r17_full.do').read_text().replace('r17','r18').replace('CONTROL_REV=13','CONTROL_REV=14')
    (ROOT/'fpga/motor_bt_drive/run_modelsim_sin12_r18_full.do').write_text(run)
    for name in ('tb_sin12_r17_wait_telemetry.sv','run_modelsim_sin12_r17_wait_telemetry.do'):
        text=(ROOT/'fpga/motor_bt_drive'/name).read_text().replace('r17','r18').replace('R17','R18')
        text=text.replace('REV5_ENABLE(13)','REV5_ENABLE(14)').replace('K11','K12')
        (ROOT/'fpga/motor_bt_drive'/name.replace('r17','r18')).write_text(text)
    good=pack_autonav_goal(0x1820,(17,2),(17,3),500,0,True)
    bad=bytearray(good);bad[-1]^=1
    oldmap=bytearray(good);oldmap[8]^=1
    from src.comm.protocol import build_frame
    obsolete=build_frame(0x26,0x1821,bytes(oldmap[8:-2]))
    legacy=pack_autonav_goal(0x1822,(17,2),(17,3),333,0,True)
    (ROOT/'fpga/motor_bt_drive/sin12_r18_packet_frames.mem').write_text(
        '\n'.join(f'{b:02x}' for packet in (good,bad,obsolete,legacy) for b in packet)+'\n')
    manifest=json.loads((OUT/'sin12_hdmi_r17_build_sources.json').read_text(encoding='utf-8-sig'))
    current={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in manifest}
    assert len(current)==58
    (OUT/'sin12_hdmi_r18_build_sources.json').write_text(json.dumps(current,indent=2))
    print(json.dumps(dict(hardware_sources=len(current),user_code='534E3252',counts_per_cell=500)))


if __name__=='__main__':main()
