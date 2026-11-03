"""Usual console: actual hidden Tk and async transport, fake serial only."""
from pathlib import Path
import struct
import sys
import time

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive'))
import pc_unified_console as console
from src.comm.pid_tuning import parse_pid_status, mission_lease_ms
from src.comm.autonav import counts_per_cell_for_version


def test_real_k14_packet_supported_without_accepting_unknown_or_bad_parameters():
    assert parse_pid_status('K14000000040100') == dict(version=20, sequence=0, status=0, p=4, i=1, d=0)
    assert counts_per_cell_for_version(20) == 500 and mission_lease_ms(20) == 600
    assert parse_pid_status('K13000000040100')['version'] == 19
    assert parse_pid_status('K15000000040100') is None
    assert parse_pid_status('K14000000210100') is None
    assert parse_pid_status('K14000004040100') is None


@pytest.mark.parametrize('case', [
    'applied', 'stale_ack', 'reject', 'unknown', 'stale_k', 'stale_o',
    'geometry', 'firmware', 'sensor', 'disconnect',
])
def test_k14_enable_requires_fresh_stopped_telemetry_and_new_board_ack(monkeypatch, tmp_path, case):
    ports, roots, texts, links, errors, inspected = [], [], [], [], [], []
    sample = ('C' + struct.pack('>HBhhb4B4h4H', 20, 0, 0, 0, 0, *([0] * 12)).hex() + '\r\n').encode()
    class Port:
        def __init__(self, *args, **kwargs):
            self.buffer = b''
            self.writes = []
            self.seq, self.flags = 0, 0
            self.started = time.monotonic()
            ports.append(self)
            self.feed(initial=True)

        def feed(self, initial=False):
            valid = 0 if case == 'sensor' else 1
            self.buffer += f'I1 T{valid} D0866 H0 F00 R00000000 P00000000 Y00000000 W0\r\n'.encode() + sample
            if initial or case != 'stale_k' or time.monotonic() - self.started < .2:
                self.buffer += b'K15000000040100\r\n' if case == 'unknown' else b'K14000000040100\r\n'
            if initial or case != 'stale_o' or time.monotonic() - self.started < .2:
                self.buffer += f'O{self.seq:02X}{self.flags:02X}000000\r\n'.encode()

        def read(self, count):
            data, self.buffer = self.buffer[:count], self.buffer[count:]
            return data

        def write(self, data):
            self.writes.append(data)
            if data == b'A':
                if case != 'stale_ack':
                    self.seq += 1
                self.flags = 8 if case == 'reject' else 5
                self.feed()
            return len(data)

        def close(self):
            pass

    tk = console.tk
    original_tk, original_var, original_link = tk.Tk, tk.StringVar, console.AsyncTrackedPort

    def variable(*args, **kwargs):
        value = original_var(*args, **kwargs)
        texts.append(value)
        return value

    def tracked_link(*args, **kwargs):
        value = original_link(*args, **kwargs)
        links.append(value)
        return value

    def descendants(widget):
        for child in widget.winfo_children():
            yield child
            yield from descendants(child)

    def make_root():
        root = original_tk()
        root.withdraw()
        roots.append(root)
        root.report_callback_exception = lambda *args: errors.append(args)
        loop = root.mainloop

        def run():
            widgets = list(descendants(root))

            def button(label):
                return next(w for w in widgets if isinstance(w, tk.Button) and w.cget('text') == label)

            button('连接').invoke()

            def feed():
                ports[0].feed()
                root.after(100, feed)

            def operate():
                for widget in widgets:
                    if isinstance(widget, tk.Checkbutton):
                        label = widget.cget('text')
                        if label == '已核对 FPGA 当前运行固件' and case != 'firmware':
                            widget.invoke()
                        if label.startswith('已核对ToF安装') and case != 'geometry':
                            widget.invoke()
                if case == 'disconnect':
                    button('断开').invoke()
                button('启用前进避障').invoke()

            def inspect():
                values = [v.get() for v in texts]
                assert ports[0].writes.count(b'A') == int(case in ('applied', 'stale_ack', 'reject'))
                assert not any(data in (b'F', b'B', b'L', b'R', b'G', b'M', b'V', b'N') for data in ports[0].writes)
                assert any('已获板端确认：避障已启用' in v for v in values) == (case == 'applied')
                if case not in ('unknown', 'disconnect'):
                    assert any('K14（R20）' in v for v in values)
                expected = {
                    'unknown': '需要R5及以后', 'stale_k': '回传已过期', 'stale_o': '回传已过期',
                    'geometry': '未勾选几何', 'firmware': '未勾选当前固件',
                    'sensor': 'IMU/ToF无效', 'disconnect': '请先连接', 'reject': '板端拒绝操作',
                }.get(case)
                if expected:
                    assert any(expected in v for v in values), values
                # User-requested hidden explanations and axis ticks remain absent.
                assert not any('边框标出' in str(w.cget('text')) for w in widgets if isinstance(w, tk.Label))
                canvas = next(w for w in widgets if isinstance(w, tk.Canvas) and int(w.cget('width')) == 440)
                assert not any(canvas.type(i) == 'text' and canvas.itemcget(i, 'text').isdigit() for i in canvas.find_all())
                inspected.append(True)
                root.quit()

            delay = 2450 if case in ('stale_k', 'stale_o') else 350
            root.after(100, feed)
            root.after(delay, operate)
            root.after(delay + 1300, inspect)
            root.after(delay + 3000, root.quit)
            loop()

        root.mainloop = run
        return root

    monkeypatch.setattr(tk, 'Tk', make_root)
    monkeypatch.setattr(tk, 'StringVar', variable)
    monkeypatch.setattr(console.serial, 'Serial', Port)
    monkeypatch.setattr(console, 'AsyncTrackedPort', tracked_link)
    monkeypatch.setattr(sys, 'argv', ['console', '--firmware', 'SIN12', '--log-dir', str(tmp_path)])
    try:
        console.main()
        assert not errors, errors
        assert inspected
    finally:
        for link in links:
            link.close()
            link._rx_thread.join(.3)
            link._tx_thread.join(.3)
        for root in roots:
            root.destroy()
