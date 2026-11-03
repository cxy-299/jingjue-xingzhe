"""Generate real Python protocol bytes and test unmodified production RTL parsers."""
import argparse
from pathlib import Path
import subprocess
from src.comm.protocol import pack_mission_request,pack_mission_observation
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentResult
from src.core.a4_targets import CLASS_BASE


def run(vsim):
    root=Path(__file__).resolve().parents[1]
    output=root/'output/board/a4_identity_protocol_20261031';output.mkdir(exist_ok=True)
    frames=[]
    for n in range(10):
        mission=0x12340000+n
        obs=TargetObservation(100,True,CLASS_BASE+n,f'a4_digit_{n}',.95,5000,5000,2000,5000)
        frames.extend([pack_mission_request(n,mission,CLASS_BASE+n,200,'any',False),
            pack_mission_observation(n,obs,VisualAlignmentResult('CENTERED',0,0,0,'test'),n,9,True,mission)])
    bad=bytearray(frames[-1]);bad[-1]^=1;frames.append(bytes(bad))
    vectors=output/'vectors.hex';vectors.write_text('\n'.join(f'{b:02x}' for frame in frames for b in frame)+'\n',encoding='ascii')
    library=(output/'work').as_posix();source=root/'fpga/motor_bt_drive'
    command='; '.join(['onerror {quit -code 1 -f}','onbreak {quit -code 1 -f}',
      f'if {{![file exists {library}]}} {{vlib {library}}}',
      f'vlog -sv -work {library} "{(root/"fpga/vision_packet_parser.v").as_posix()}" "{(source/"bt_mission_packet_rx.v").as_posix()}" "{(source/"tb_a4_identity_protocol.sv").as_posix()}"',
      f'vsim -c -lib {library} tb_a4_identity_protocol +vectors={vectors.as_posix()}',
      'run -all','quit -f'])
    result=subprocess.run([str(vsim),'-c','-do',command],capture_output=True,text=True,cwd=root)
    log=result.stdout+result.stderr;(output/'simulation.log').write_text(log,encoding='utf8')
    print(log)
    if result.returncode or 'A4_R12_PRODUCTION_BYTE_PARSERS_10_DIGIT_IDS_AND_BAD_CRC_PASS' not in log:raise SystemExit(1)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--vsim',type=Path,required=True)
    run(parser.parse_args().vsim)

