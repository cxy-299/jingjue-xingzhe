"""Real Tk callbacks with fake serial: O telemetry must not erase button results."""
from pathlib import Path
import struct
import sys
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive'))
import pc_unified_console as console


@pytest.mark.parametrize('version', [12, 15])
@pytest.mark.parametrize('geometry_confirmed', [False, True])
def test_enable_feedback_survives_periodic_status(monkeypatch, tmp_path, version, geometry_confirmed):
    ports, roots, variables, errors = [], [], [], []
    sample = ('C' + struct.pack('>HBhhb4B4h4H', 20, 0, 0, 0, 0, *([0]*12)).hex() + '\r\n').encode()
    tuning = ('K' + struct.pack('>BHBBBB', version, 0, 0, 4, 1, 0).hex() + '\r\n').encode()
    class Port:
        def __init__(self, *args, **kwargs):
            self.buffer = b''; self.writes = []; self.enabled = False; self.seq = 0
            ports.append(self); self.feed()
        def feed(self):
            self.buffer += (b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\n' + sample + tuning +
                            f'O{self.seq:02X}{5 if self.enabled else 0:02X}000000\r\n'.encode())
        def read(self, count):
            data, self.buffer = self.buffer[:count], self.buffer[count:]; return data
        def write(self, data):
            self.writes.append(data)
            if data == b'A': self.enabled = True; self.seq += 1; self.feed()
            return len(data)
        def close(self): pass
    tk = console.tk
    original_tk, original_var = tk.Tk, tk.StringVar
    def var(*args, **kwargs):
        value = original_var(*args, **kwargs); variables.append(value); return value
    def descendants(widget):
        for child in widget.winfo_children(): yield child; yield from descendants(child)
    def make_root():
        try: root = original_tk()
        except tk.TclError as exc: pytest.skip(str(exc))
        roots.append(root); root.withdraw(); loop = root.mainloop
        root.report_callback_exception = lambda *args: errors.append(args)
        def run():
            widgets = list(descendants(root))
            next(w for w in widgets if isinstance(w, tk.Button) and w.cget('text') == '连接').invoke()
            def feed():
                ports[0].feed(); root.after(120, feed)
            def operate():
                for w in widgets:
                    if isinstance(w, tk.Checkbutton):
                        text = w.cget('text')
                        if text == '已核对 FPGA 当前运行固件' or (geometry_confirmed and text.startswith('已核对ToF齐平')):
                            w.invoke()
                next(w for w in widgets if isinstance(w, tk.Button) and w.cget('text') == '启用前进避障').invoke()
            root.after(180, feed); root.after(350, operate)
            root.after(1600, root.quit); loop()
        root.mainloop = run; return root
    monkeypatch.setattr(tk, 'Tk', make_root); monkeypatch.setattr(tk, 'StringVar', var)
    monkeypatch.setattr(console.serial, 'Serial', Port)
    monkeypatch.setattr(sys, 'argv', ['console', '--log-dir', str(tmp_path)])
    try:
        console.main(); assert not errors, errors
        values = [v.get() for v in variables]
        assert ports[0].writes.count(b'A') == int(geometry_confirmed)
        assert not any(w in (b'F', b'B', b'L', b'R', b'G', b'M', b'V', b'N') for w in ports[0].writes)
        if geometry_confirmed:
            assert any('已获板端确认' in value for value in values), values
        else:
            assert any('未勾选' in value and '几何' in value for value in values), values
    finally:
        for root in roots: root.destroy()
