"""把仿真器导出的真实 VCD 绘成可复核的 UART 验收波形图。"""

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


HERE = Path(__file__).resolve().parent
VCD = HERE / "uart_verify_xsim.vcd"


def read_vcd(path):
    # VCD 时间单位为 1 ps。用标识符映射信号名，再保存每次变化的时间和值。
    names = {}
    traces = {}
    now_ps = 0
    definitions_done = False
    with path.open(encoding="ascii") as source:
        for line in source:
            line = line.strip()
            if line.startswith("$var"):
                parts = line.split()
                names[parts[3]] = parts[4]
                traces[parts[4]] = []
            elif line == "$enddefinitions $end":
                definitions_done = True
            elif definitions_done and line.startswith("#"):
                now_ps = int(line[1:])
            elif definitions_done and line and not line.startswith("$"):
                if line.startswith("b"):
                    raw, code = line[1:].split()
                else:
                    raw, code = line[0], line[1:]
                if code in names and set(raw) <= {"0", "1"}:
                    traces[names[code]].append((now_ps / 1e9, int(raw, 2)))
    return traces


def plot(traces, end_ms, filename, title):
    fig, ax = plt.subplots(figsize=(17, 8.5), dpi=150)
    colors = {
        "uart_rx": "#607d8b", "link_alive": "#1976d2",
        "vision_fresh": "#00897b", "target_valid": "#8e24aa",
        "target_confirmed": "#d81b60", "vision_pulse": "#e65100",
        "crc_errors": "#c62828", "vision_pulses": "#2e7d32",
    }
    rows = list(colors)
    for row, name in enumerate(rows):
        events = traces[name]
        times = [time for time, _ in events] + [end_ms]
        values = [value for _, value in events] + [events[-1][1]]
        if name in ("crc_errors", "vision_pulses"):
            scaled = [row + 0.72 - min(value, 3) * 0.2 for value in values]
        else:
            scaled = [row + 0.72 - value * 0.6 for value in values]
        ax.step(times, scaled, where="post", lw=1.4,
                color=colors[name], label=name)
        if name == "vision_pulse":
            for time, value in events:
                if value:
                    ax.plot(time, row + 0.12, marker="o", ms=5,
                            color=colors[name])
    steps = traces["test_step"]
    for index, (start, number) in enumerate(steps):
        stop = steps[index + 1][0] if index + 1 < len(steps) else end_ms
        if start >= end_ms:
            break
        ax.axvspan(start, min(stop, end_ms), alpha=0.055,
                   color="#1565c0" if number % 2 else "#f57c00")
        if stop - start > end_ms * 0.025:
            ax.text((start + min(stop, end_ms)) / 2, -0.38,
                    str(number), ha="center", va="center", fontsize=9)
    ax.set(yticks=[row + 0.4 for row in range(len(rows))],
           yticklabels=rows, ylim=(len(rows) - 0.05, -0.8),
           xlim=(0, end_ms), xlabel="Simulation time (ms)", title=title)
    ax.grid(axis="x", color="#d7dee5", lw=0.7)
    ax.text(0.0, -0.68, "test_step:", fontsize=9, ha="left")
    fig.tight_layout()
    fig.savefig(HERE / filename, facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    signals = read_vcd(VCD)
    final_ms = max(time for events in signals.values() for time, _ in events)
    plot(signals, final_ms, "uart_wave_overview.png",
         "UART acceptance: heartbeat, vision, CRC rejection and timeouts")
    plot(signals, 8.5, "uart_wave_packets.png",
         "UART acceptance: first heartbeat, valid vision frame and bad CRC")
    print(f"VCD duration: {final_ms:.3f} ms")
    for name in ("test_step", "link_alive", "vision_fresh",
                 "target_valid", "vision_pulses", "crc_errors"):
        print(name, signals[name])
