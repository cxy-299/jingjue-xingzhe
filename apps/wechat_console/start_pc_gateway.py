"""Run an opt-in desktop console gateway; does not connect Bluetooth automatically."""
import argparse
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
sys.path.insert(0,str(PROJECT))
sys.path.insert(0,str(PROJECT/'fpga/motor_bt_drive'))

def main():
    parser=argparse.ArgumentParser(description='境觉行者电脑中转驾驶台')
    parser.add_argument('--host',default='0.0.0.0')
    parser.add_argument('--gateway-port',type=int,default=8765)
    parser.add_argument('--pi-base',default='http://192.168.137.129:8080')
    args,remaining=parser.parse_known_args()
    from gateway.pc_adapter import factory
    import pc_unified_console
    sys.argv=['pc_unified_console','--firmware','SIN12',*remaining]
    pc_unified_console.main(remote_factory=factory(args.host,args.gateway_port,args.pi_base))

if __name__=='__main__':main()
