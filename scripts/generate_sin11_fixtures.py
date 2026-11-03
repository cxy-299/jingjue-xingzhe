"""Generate HDL fixtures from the deployed host protocol implementation."""
from pathlib import Path
from types import SimpleNamespace
from src.comm.protocol import pack_mission_request, pack_mission_observation
from src.core.messages import TargetObservation


def main():
    target=Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'
    request=pack_mission_request(1,0x47534642,39,200,'red')
    bad=bytearray(request);bad[-1]^=0x80
    obs=TargetObservation(100,True,39,'bottle',.95,5000,5000,2000,2000)
    frame=pack_mission_observation(2,obs,
        SimpleNamespace(state='CENTERED',center_error=0,vy=0),3,42,True,0x47534642,'red')
    for name,data in [('sin11_request_frames.mem',request+bad),('sin11_observation_frame.mem',frame)]:
        (target/name).write_text('\n'.join(f'{b:02x}' for b in data)+'\n')


if __name__=='__main__':main()
