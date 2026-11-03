from src.comm.serial_link import SerialLink
from types import SimpleNamespace


class FakeSerial:
    def __init__(self, port, baudrate, timeout, write_timeout):
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.write_timeout = write_timeout
        self.is_open = True
        self.output = bytearray()

    def write(self, data):
        self.output.extend(data)
        return len(data)

    def close(self):
        self.is_open = False


def test_serial_link_sends_complete_frame_and_counts_bytes():
    link = SerialLink(
        enabled=True,
        port='/dev/serial0',
        serial_factory=FakeSerial,
    )
    assert link.open() is True
    assert link.send(b'\xAA\x55\x03') is True
    assert bytes(link.ser.output) == b'\xAA\x55\x03'
    assert link.frames_sent == 1
    assert link.bytes_sent == 3
    assert link.status()['connected'] is True


def test_serial_link_failure_is_nonfatal():
    def failing_factory(*_args, **_kwargs):
        raise OSError('port missing')

    link = SerialLink(
        enabled=True,
        port='/dev/missing',
        serial_factory=failing_factory,
    )
    assert link.open() is False
    assert link.send(b'test') is False
    assert link.status()['connected'] is False
    assert 'port missing' in link.status()['last_error']


def test_usb_ch340_auto_select_and_last_frame_status():
    ports = [
        SimpleNamespace(device='/dev/ttyUSB0', vid=0x1A86,
                        pid=0x7523, description='USB-SERIAL CH340'),
        SimpleNamespace(device='/dev/ttyACM0', vid=0x2341,
                        pid=0x0043, description='Other serial'),
    ]
    link = SerialLink(enabled=True, port='auto_usb_ch340',
                      serial_factory=FakeSerial, port_lister=lambda: ports)
    assert link.open() is True
    assert link.ser.port == '/dev/ttyUSB0'
    assert link.send(bytes.fromhex('aa 55 03 13 2a 00 00 00 00 00'))
    status = link.status()
    assert status['active_port'] == '/dev/ttyUSB0'
    assert status['last_msg_type'] == 0x13
    assert status['last_seq'] == 42
    assert status['last_sent_age_ms'] is not None


def test_usb_ch340_auto_rejects_ambiguous_ports():
    ports = [SimpleNamespace(device=f'/dev/ttyUSB{i}', vid=0x1A86,
                             pid=0x7523, description='CH340') for i in range(2)]
    link = SerialLink(enabled=True, port='auto_usb_ch340',
                      serial_factory=FakeSerial, port_lister=lambda: ports)
    assert link.open() is False
    assert 'found 2' in link.status()['last_error']
