"""Check the default profile and mode interlock using real Tk, fake serial only."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpga/motor_bt_drive'))
import pc_unified_console as console


def test_default_sin12_has_no_firmware_picker_or_legacy_nav(monkeypatch, tmp_path):
    tk = console.tk
    original = tk.Tk
    roots, errors, opened = [], [], []

    def descendants(w):
        for child in w.winfo_children():
            yield child
            yield from descendants(child)

    def root_factory():
        try:
            root = original()
        except tk.TclError as exc:
            pytest.skip(str(exc))
        roots.append(root)
        root.withdraw()
        root.report_callback_exception = lambda *args: errors.append(args)
        real_loop = root.mainloop

        def verify():
            widgets = list(descendants(root))
            label = next(w for w in widgets if w.winfo_name() == 'fixed_firmware')
            assert 'SIN12' in label.cget('text')
            combos = [str(w.cget('values')) for w in widgets if isinstance(w, console.ttk.Combobox)]
            assert not any('SIN9' in value or 'SIN12' in value for value in combos)
            modes = {w.cget('text'): w for w in widgets if isinstance(w, tk.Radiobutton)}
            assert '旧版路径执行' not in modes
            assert '定点旋转' not in modes
            buttons={w.cget('text') for w in widgets if isinstance(w,tk.Button)}
            assert {'左转90°','右转90°'} <= buttons
            for name in ('手动', '板内规划绕障', '距离跟随', '指定目标跟随', '智能任务', '安全停车'):
                modes[name].invoke()
            assert not opened, 'Opening UI and changing modes must not connect or move hardware'
            root.quit()
        root.mainloop = lambda: (root.after(10, verify), root.after(1000, root.quit), real_loop())
        return root

    monkeypatch.setattr(tk, 'Tk', root_factory)
    monkeypatch.setattr(console.serial, 'Serial', lambda *a, **k: opened.append((a, k)))
    monkeypatch.setattr(sys, 'argv', ['console', '--log-dir', str(tmp_path)])
    try:
        console.main()
        assert not errors, errors
        assert not opened
    finally:
        for root in roots:
            root.destroy()
