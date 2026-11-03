import struct
import pytest
from src.comm.pid_tuning import pack_pid_config, parse_pid_status, parse_wheel_sample
from src.comm.protocol import parse_frame


def test_packet_crc_and_ranges():
    packet=parse_frame(pack_pid_config(0xF17E,4,1,0))
    assert packet['msg_type']==0x27 and packet['seq']==0xF17E
    assert packet['payload']==struct.pack('<HHH',4,1,0)
    for gains in ((33,1,0),(4,9,0),(4,1,-1),(4.0,1,0)):
        with pytest.raises(ValueError):pack_pid_config(1,*gains)


def test_real_applied_readback_and_atomic_sample():
    assert parse_pid_status('K04F17E01040100')==dict(version=4,sequence=0xF17E,status=1,p=4,i=1,d=0)
    data=struct.pack('>HBhhb4B4h4H',65535,9,10000,-800,-2,22,18,22,18,21,19,20,18,700,701,702,703)
    sample=parse_wheel_sample('C'+data.hex())
    assert sample['sequence']==65535 and sample['heading_locked'] and sample['command']==1
    assert sample['targets']==(22,18,22,18) and sample['speeds']==(21,19,20,18)
    assert sample['duties']==(700,701,702,703) and sample['correction']==-2
    assert parse_pid_status('K03000000040100') is None
    assert parse_wheel_sample('C00') is None
