"""Adapt old test stimulus, never old netlist/PASS evidence or interfaces."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]


def main():
    text=(ROOT/'fpga/motor_bt_drive/tb_sin12_r17_mapped_nav.sv').read_text()
    text=text.replace('r17','r18').replace('R17','R18').replace('333','500')
    text=text.replace('p0<300 || p0>350','p0<450 || p0>525')
    # Preserve separate 125mm projection test. For full detour completion the
    # second obstacle's stopped near ray is300mm:125mm plus the preserved210mm
    # inflation would correctly forbid a100mm dogleg. Never shrink inflation
    # or override occupancy merely to force a fixed manoeuvre to complete.
    text=text.replace('repeat(8)step;distance=125;emit=1;j=0;',
                      'repeat(8)step;distance=300;emit=1;j=0;')
    text=text.replace('R18_MAPPED_NAV_TWO_NEW_LOCAL_OBSTACLES_REPLAN_ORIGINAL_GOAL_PASS',
                      'R18_MAPPED_NAV_TWO_NEW_LOCAL_OBSTACLES_LEFT_DETOUR_ORIGINAL_GOAL_PASS')
    text=text.replace('integer n,j,yy,events,firstox,firstoy,last_mark_position;',
                      'integer n,j,yy,events,firstox,firstoy,last_mark_position;')
    (ROOT/'fpga/motor_bt_drive/tb_sin12_r18_mapped_nav.sv').write_text(text)


if __name__=='__main__':main()
