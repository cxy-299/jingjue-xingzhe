"""Interleaved telemetry stays usable; an actual driver error fails closed."""
from pathlib import Path
import sys
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive'))
import pc_unified_console as console


@pytest.mark.parametrize('fail_first_read', [False, True])
def test_interleaved_receive_or_driver_error_fails_closed(monkeypatch, fail_first_read):
    payload = (
        'M4 T020 A+004 D0000 F0\r\n'
        'I1 T1 D0400 H0 F00 R3F800000 P00000000 Y00000000 W0\r\n'
        'V1 L1 C0027 K0000002A S02 A0\r\n'
        'M1 T020 A+001 D0000 F0\r\n'
        'M2 T020 A+002 D0000 F0\r\n'
        'M3 T020 A+003 D0000 F0\r\n'
    ).encode('ascii')

    class Port:
        def __init__(self, *args, **kwargs):
            self.buffer = payload
            self.writes = []
            self.failed = False

        def read(self, count):
            if fail_first_read and not self.failed:
                self.failed = True
                raise ValueError('injected receive callback error')
            data, self.buffer = self.buffer[:count], self.buffer[count:]
            return data

        def write(self, data):
            self.writes.append(data)
            return len(data)

        def close(self):
            pass

    tk = console.tk
    original_tk, original_string = tk.Tk, tk.StringVar
    values, callback_errors, roots = [], [], []

    def string_var(*args, **kwargs):
        value = original_string(*args, **kwargs)
        values.append(value)
        return value

    def descendants(widget):
        for child in widget.winfo_children():
            yield child
            yield from descendants(child)

    def make_root():
        try:
            root = original_tk()
        except tk.TclError as error:
            pytest.skip(f'Tk runtime unavailable: {error}')
        roots.append(root)
        root.withdraw()
        real_loop = root.mainloop
        root.report_callback_exception = lambda *args: callback_errors.append(args)

        def run():
            connect = next(w for w in descendants(root)
                           if isinstance(w, tk.Button) and w.cget('text') == '连接')
            root.after(1, connect.invoke)
            root.after(500, root.quit)
            real_loop()

        root.mainloop = run
        return root

    monkeypatch.setattr(tk, 'Tk', make_root)
    monkeypatch.setattr(tk, 'StringVar', string_var)
    monkeypatch.setattr(console.serial, 'Serial', Port)
    monkeypatch.setattr(sys, 'argv', ['pc_unified_console.py', '--port', 'COM9'])
    try:
        console.main()
        texts = [v.get() for v in values]
        assert not callback_errors, callback_errors
        if fail_first_read:
            # AsyncTrackedPort treats a port.read exception as a broken link.
            # Do not silently resume hardware control after a driver failure.
            assert any('已断开' in t and ('故障' in t or '失败' in t) for t in texts), texts
            assert all(not any(t.startswith(f'M{i} T020') for t in texts) for i in range(1, 5))
            return
        for index in range(1, 5):
            assert any(t.startswith(f'M{index} T020 A+00{index}') for t in texts), texts
        assert any('蓝牙 COM9' in t and '400 mm' in t for t in texts), texts
        assert any('IMU 姿态' in t and '+57.3' in t for t in texts), texts
        assert any('bottle #42' in t and 'A0' in t for t in texts), texts
    finally:
        for root in roots:
            root.destroy()


@pytest.mark.parametrize('geometry', ['1040x650', '1280x850'])
def test_telemetry_and_logs_remain_visible_when_controls_overflow(monkeypatch, geometry):
    tk = console.tk
    original_tk = tk.Tk
    roots, errors = [], []

    def descendants(widget):
        for child in widget.winfo_children():
            yield child
            yield from descendants(child)

    def make_root():
        try:
            root = original_tk()
        except tk.TclError as error:
            pytest.skip(str(error))
        roots.append(root)
        root.report_callback_exception = lambda *args: errors.append(args)

        def verify():
            root.geometry(geometry)
            root.update()
            widgets = list(descendants(root))
            history = next(w for w in widgets if w.winfo_name() == 'serial_history')
            diagnostics = next(w for w in widgets if w.winfo_name() == 'diagnostics')
            for widget in (history, diagnostics):
                assert widget.winfo_ismapped()
                top = widget.winfo_rooty()-root.winfo_rooty()
                assert top >= 0
                assert top+widget.winfo_height() <= root.winfo_height()
            assert history.winfo_height() >= 65
            assert history.winfo_width() >= 400
            stop_buttons = [w for w in widgets if isinstance(w, tk.Button)
                            and w.cget('text') == '停止 S']
            assert any(w.winfo_rooty()-root.winfo_rooty() < 90 for w in stop_buttons)
            controls = next(w for w in widgets if isinstance(w, console.ScrollPanel)
                            and w.inner.winfo_reqheight() > w.canvas.winfo_height()
                            and any(isinstance(c, tk.LabelFrame) and '蓝牙 COM9' in c.cget('text')
                                    for c in w.inner.winfo_children()))
            controls.canvas.yview_moveto(1)
            root.update()
            assert controls.canvas.yview()[0] > 0
            assert history.winfo_rooty()+history.winfo_height() <= root.winfo_rooty()+root.winfo_height()
            assert not errors, errors

        root.mainloop = verify
        return root

    monkeypatch.setattr(tk, 'Tk', make_root)
    monkeypatch.setattr(sys, 'argv', ['pc_unified_console.py'])
    try:
        console.main()
    finally:
        for root in roots:
            root.destroy()
