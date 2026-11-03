from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive'))
from pc_follow_sequence import FollowCommandSequencer


class Gate:
    def __init__(self): self.held = 'F'; self.events = []
    def stop(self): self.held = None; self.events.append('S')
    def press(self, d): self.held = d; self.events.append(d)
    def refresh(self): self.events.append(self.held)


def setup():
    callbacks = []
    gate = Gate()
    seq = FollowCommandSequencer(lambda ms, fn: (callbacks.append(fn) or len(callbacks)),
                                  lambda timer: None, lambda: gate)
    return seq, gate, callbacks


def test_distance_hold_cancels_already_scheduled_reverse():
    seq, gate, callbacks = setup()
    seq.send('B')
    assert gate.events == ['S']
    seq.send('S')
    callbacks[0]()  # Even a callback already in the event queue must be harmless.
    assert gate.held is None and gate.events == ['S', 'S']


def test_new_follow_session_does_not_inherit_old_direction():
    seq, gate, callbacks = setup()
    seq.send('B'); seq.cancel(); seq.send('F'); callbacks[0]()
    assert gate.held == 'F' and gate.events == ['S', 'F']


def test_reversal_waits_once_and_duplicate_ticks_do_not_delay_it():
    seq, gate, callbacks = setup()
    seq.send('B'); seq.send('B')
    assert len(callbacks) == 1 and gate.events == ['S']
    callbacks[0](); seq.send('B')
    assert gate.events == ['S', 'B', 'B']


def test_delayed_driver_error_reaches_fault_handler():
    import serial
    seq, gate, callbacks = setup()
    errors=[];seq.on_error=errors.append
    seq.send('B')
    def broken(d):raise serial.SerialException('write failed')
    gate.press=broken
    callbacks[0]()
    assert len(errors)==1 and seq.timer is None and gate.held is None
