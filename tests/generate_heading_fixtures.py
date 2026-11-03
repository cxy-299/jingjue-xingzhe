"""Generate independent host-packed protocol/yaw inputs for the RTL test."""
from pathlib import Path
import struct
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from src.comm.protocol import pack_turn_relative, pack_nav_path, build_frame


def main():
    folder=Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'
    frames=[pack_turn_relative(1,15),pack_turn_relative(2,-30),
            pack_turn_relative(3,5),pack_turn_relative(4,30,yaw_inverted=True),
            pack_turn_relative(0x5653,169.75),pack_turn_relative(5,90)]
    data=b''.join(frames)
    (folder/'sin10_turn_frames.mem').write_text(' '.join(f'{b:02x}' for b in data)+'\n')
    angles=[0,15,18,30,-15,-30,90,179,-179,-176]
    import math
    (folder/'sin10_yaw_bits.mem').write_text('\n'.join(f'{struct.unpack("<I",struct.pack("<f",math.radians(d)))[0]:08x}' for d in angles)+'\n')


if __name__=='__main__':main()
