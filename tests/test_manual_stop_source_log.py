"""Real hidden Tk callbacks: trace a mouse release, with fake serial only."""
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive'))
import pc_unified_console as console


def test_hold_release_keeps_stop_and_records_its_origin(monkeypatch, tmp_path):
    roots, ports, links, errors, checked = [], [], [], [], []
    sample = ('C' + struct.pack('>HBhhb4B4h4H', 1, 0, 0, 0, 0, *([0] * 12)).hex() + '\r\n').encode()

    class Port:
        def __init__(self, *args, **kwargs):
            self.buffer = b'I1 T1 D1000 H0 F00 R00000000 P00000000 Y00000000 W0\r\nK14000000040100\r\nO0105000000\r\n' + sample
            self.writes = []
            ports.append(self)

        def read(self, n):
            data, self.buffer = self.buffer[:n], self.buffer[n:]
            return data

        def write(self, data):
            self.writes.append(data)
            return len(data)

        def close(self):
            pass

    tk = console.tk
    original_tk, original_link = tk.Tk, console.AsyncTrackedPort

    def descendants(widget):
        for child in widget.winfo_children():
            yield child
            yield from descendants(child)

    def tracked_link(*args, **kwargs):
        link = original_link(*args, **kwargs)
        links.append(link)
        return link

    def make_root():
        root = original_tk()
        root.withdraw()
        root.report_callback_exception = lambda *args: errors.append(args)
        roots.append(root)
        loop = root.mainloop

        def run():
            widgets = list(descendants(root))
            next(w for w in widgets if isinstance(w, tk.Button) and w.cget('text') == '连接').invoke()

            def press():
                for widget in widgets:
                    if isinstance(widget, tk.Checkbutton) and (
                        widget.cget('text') == '已核对 FPGA 当前运行固件'
                        or widget.cget('text').startswith('四轮离地或已核对')
                    ):
                        widget.invoke()
                next(w for w in widgets if isinstance(w, tk.Button) and w.cget('text') == '前 F').event_generate('<ButtonPress-1>', x=5, y=5)

            def release():
                next(w for w in widgets if isinstance(w, tk.Button) and w.cget('text') == '前 F').event_generate('<ButtonRelease-1>', x=5, y=5)

            def inspect():
                assert b'F' in ports[0].writes
                assert ports[0].writes[-1] == b'S'
                log = next(tmp_path.glob('console_*.log')).read_text(encoding='utf-8')
                assert 'UI DIRECTION source=mouse direction=F accepted=True' in log
                assert 'UI STOP source=release_direction:' in log
                assert 'UI RELEASE type=' in log
                checked.append(True)
                root.quit()

            root.after(250, press)
            root.after(600, release)
            root.after(1000, inspect)
            root.after(2500, root.quit)
            loop()

        root.mainloop = run
        return root

    monkeypatch.setattr(tk, 'Tk', make_root)
    monkeypatch.setattr(console.serial, 'Serial', Port)
    monkeypatch.setattr(console, 'AsyncTrackedPort', tracked_link)
    monkeypatch.setattr(sys, 'argv', ['console', '--log-dir', str(tmp_path)])
    try:
        console.main()
        assert not errors, errors
        assert checked
    finally:
        for link in links:
            link.close()
            link._rx_thread.join(.3)
            link._tx_thread.join(.3)
        for root in roots:
            root.destroy()
