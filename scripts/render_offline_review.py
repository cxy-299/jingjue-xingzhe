"""从本轮真实 ModelSim VCD 导出波形，保留可追溯的数据文件。"""
from pathlib import Path
from scripts.render_nav_wave import read_vcd, panel, plt, value_at

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/review"
SIM = OUT / "sim_20261016"


def main():
    plt.rcParams.update({"font.family": "Microsoft YaHei", "axes.unicode_minus": False,
                         "figure.facecolor": "#101a29", "axes.facecolor": "#152235",
                         "axes.labelcolor": "white", "xtick.color": "white",
                         "ytick.color": "white", "text.color": "white"})
    data = read_vcd(SIM / "robot_core_pipeline.vcd")
    prefix = "tb_robot_core_pipeline/"
    get = lambda name: data[prefix + name]
    # 在完整控制核心中，第一次 duty=4 对应目标 12 减去本周期测速 8。
    changed = next(t for t, v in get("dut/wheel_fl_duty[15:0]") if v == 4)
    fig, axes = plt.subplots(3, 1, figsize=(15, 10), layout="constrained")
    panel(axes[0], [("UART RX", get("uart_rx")), ("链路存活", get("link_alive")),
                    ("视觉新鲜", get("vision_fresh")), ("驱动允许", get("enabled")),
                    ("ToF 有效", get("tof_valid")), ("急停", get("estop"))],
          (0, 38), "完整核心仿真：真实 UART、故障关断、旧视觉过期与链路超时")
    # 在随后的 ToF 故障之前截断放大窗，避免将故障清零误画成轮间串扰。
    window = (changed - 0.003, changed + 0.0007)
    panel(axes[1], [("采样 tick", get("dut/control_tick")),
                    ("PID tick", get("dut/pid_tick")),
                    ("测速达到 8", get("fl_speed[3]"))], window,
          "采样与 PID 分拍：先锁存测速，再用新反馈计算本轮占空比")
    colors = ["#f7bf4f", "#66d9ef", "#a4e28c"]
    for name, label, color in zip(["dut/wheel_fl_target_counts[15:0]",
                                  "dut/wheel_fl_duty[15:0]", "dut/wheel_fr_duty[15:0]"],
                                 ["前左目标：12 计数/周期", "前左 duty：12 → 4 千分比",
                                  "前右 duty：保持 12 千分比"], colors):
        events = get(name)
        points = [(window[0], value_at(events, window[0]))]
        points += [(t, v) for t, v in events if window[0] < t < window[1]]
        points.append((window[1], value_at(events, window[1])))
        axes[2].step([t for t, _ in points], [v for _, v in points],
                     where="post", label=label, color=color)
    axes[2].set(xlim=window, ylim=(-1, 15), xlabel="时间 / ms", ylabel="数值")
    axes[2].grid(alpha=0.3)
    axes[2].legend(facecolor="#152235", labelcolor="white", loc="lower right")
    axes[2].set_title("只有前左轮反馈改变，前右轮输出保持独立；非实车稳定性测量", loc="left", color="white")
    fig.savefig(OUT / "robot_core_pipeline_wave.png", dpi=150)
    plt.close(fig)

    data = read_vcd(SIM / "packet_parser_timeout.vcd")
    prefix = "tb_packet_parser_timeout/"
    get = lambda name: data[prefix + name]
    fig, ax = plt.subplots(figsize=(14, 5), layout="constrained")
    # 此 testbench 缩短字节超时到 8 拍，仅验证状态机，不代表实机采用 8 拍超时。
    end = max(t for events in data.values() for t, _ in events)
    panel(ax, [("输入字节有效", get("byte_valid")),
               ("发布有效目标", get("goal_valid"))], (0, end),
          "协议仿真：半帧超时 → 正确目标 → 四类拒绝帧 → 正确目标（仅两次发布）")
    fig.savefig(OUT / "packet_parser_timeout_wave.png", dpi=150)
    print(OUT / "robot_core_pipeline_wave.png")
    print(OUT / "packet_parser_timeout_wave.png")


if __name__ == "__main__":
    main()
