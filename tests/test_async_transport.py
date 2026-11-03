import sys
import threading
import time
from pathlib import Path

import pytest
import serial

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'fpga/motor_bt_drive'))
from pc_async_transport import AsyncTrackedPort


def eventually(predicate, timeout=1):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        if predicate():return
        time.sleep(.005)
    assert predicate()


def test_blocked_receive_does_not_block_gui_poll_or_transmit():
    class Port:
        def __init__(self):self.release=threading.Event();self.writes=[]
        def read(self,n):self.release.wait();return b''
        def write(self,b):self.writes.append(b);return len(b)
        def close(self):self.release.set()
    raw=Port();link=AsyncTrackedPort(raw)
    try:
        start=time.monotonic();assert link.poll_lines()==[]
        assert time.monotonic()-start<.1
        link.write(b'M');eventually(lambda:raw.writes==[b'M'])
        assert link.tx_bytes==1
    finally:link.close()


def test_stop_drops_queued_motion_and_frames():
    class Port:
        def __init__(self):self.first=threading.Event();self.release=threading.Event();self.writes=[]
        def read(self,n):return b''
        def write(self,b):
            if not self.writes:self.first.set();self.release.wait(.2)
            self.writes.append(b);return len(b)
        def close(self):self.release.set()
    raw=Port();link=AsyncTrackedPort(raw)
    try:
        link.write(b'3');assert raw.first.wait(1)
        link.write(b'F');link.write(b'\xaa\x55pending');link.write(b'M');link.write(b'S')
        raw.release.set();eventually(lambda:len(raw.writes)==2)
        assert raw.writes==[b'3',b'S']
    finally:link.close()


def test_short_write_revokes_queue_and_surfaces_error():
    class Port:
        def read(self,n):return b''
        def write(self,b):return 0
        def close(self):pass
    link=AsyncTrackedPort(Port())
    try:
        link.write(b'M');eventually(lambda:link._error is not None)
        assert link.tx_bytes==0
        with pytest.raises(serial.SerialException):link.poll_lines()
        with pytest.raises(serial.SerialException):link.write(b'F')
    finally:link.close()


def test_long_write_is_reported_and_never_treated_as_healthy_lease():
    class Port:
        def read(self,n):return b''
        def write(self,b):time.sleep(.28);return len(b)
        def close(self):pass
    link=AsyncTrackedPort(Port())
    try:
        start=time.monotonic();link.write(b'M')
        assert time.monotonic()-start<.1
        eventually(lambda:link._error is not None)
        assert not link._pending
        with pytest.raises(serial.SerialException,match='250ms'):link.poll_lines()
    finally:link.close()


def test_close_attempts_priority_stop_without_waiting_for_driver_read():
    class Port:
        def __init__(self):self.release=threading.Event();self.writes=[];self.closed=False
        def read(self,n):self.release.wait();return b''
        def write(self,b):self.writes.append(b);return len(b)
        def close(self):self.closed=True;self.release.set()
    raw=Port();link=AsyncTrackedPort(raw)
    start=time.monotonic();link.close()
    assert time.monotonic()-start<.2
    assert raw.writes==[b'S'] and raw.closed
