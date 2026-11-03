"""Create NEW R19 verification files. Never copies a previous PASS report."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'

def new_copy(source, replacements=()):
    old=ROOT/source;target=ROOT/source.replace('r18','r19')
    assert not target.exists(),target
    text=old.read_text(encoding='utf8').replace('r18','r19').replace('R18','R19').replace('534E3252','534E3253')
    for a,b in replacements:text=text.replace(a,b)
    target.write_text(text,encoding='utf8')

def main():
    for name in ('build_sin12_r18.ps1','inspect_sin12_r18_timing.py','audit_sin12_r18_constraints.py',
                 'verify_sin12_r18_mapped_tof.py','verify_sin12_r18_mapped_target.py','verify_sin12_r18_mapped_nav.py'):
        new_copy('scripts/'+name)
    for name in ('tb_sin12_r18_full.sv','run_modelsim_sin12_r18_full.do',
                 'tb_sin12_r18_wait_telemetry.sv','run_modelsim_sin12_r18_wait_telemetry.do',
                 'sin12_r18_packet_frames.mem'):
        new_copy('fpga/motor_bt_drive/'+name,[('CONTROL_REV=14','CONTROL_REV=15'),('REV5_ENABLE(14)','REV5_ENABLE(15)'),('K12','K13')])
    new_copy('fpga/motor_bt_drive/run_modelsim_sin12_r18_left_detour.do')
    new_copy('fpga/motor_bt_drive/tb_sin12_r18_left_detour.sv',[
        ('.FIXED_LEFT_DETOUR(1))','.FIXED_LEFT_DETOUR(1),.DETOUR_FORWARD_CELLS(3),.LATCH_NEAR_EVENT(1))'),
        ('directions[3]!=3','directions[3]!=0 || directions[4]!=0 || directions[5]!=3'),
        ('directions[3]!=2','directions[3]!=3 || directions[4]!=3 || directions[5]!=2'),
        ('LEFT_ONE_FORWARD_ONE_RIGHT_ONE','LEFT_ONE_FORWARD_THREE_RIGHT_ONE')])
    new_copy('fpga/motor_bt_drive/tb_sin12_r18_mapped_nav.sv',[
        ('tracked_legs<3','tracked_legs<5'),
        ('observed_directions[2]!=3','observed_directions[2]!=0 || observed_directions[3]!=0 || observed_directions[4]!=3'),
        ('LEFT_FORWARD_RIGHT_RESTORE','LEFT_FORWARD_THREE_RIGHT_RESTORE')])
    hardware=json.loads((OUT/'sin12_hdmi_r18_build_sources.json').read_text())
    (OUT/'sin12_hdmi_r19_build_sources.json').write_text(json.dumps({n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in hardware},indent=2))
    print('R19 scaffolding created; all new reports still pending')

if __name__=='__main__':main()
