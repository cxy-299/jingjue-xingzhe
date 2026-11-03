"""Read the isolated replication experiment; never program hardware or alter baseline."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / 'output/board'
NAME = 'acg720_motor_bt_autonav'


def paths(text):
    section = text.split('3.3.1 Setup Analysis Report', 1)[-1]
    blocks = re.split(r'\bPath\d+\b', section)
    result = []
    for block in blocks:
        if 'Path Summary:' not in block:
            continue
        if len(result) == 10:
            break
        def get(pattern):
            return re.search(pattern, block).group(1)
        arrival = block.split('Data Arrival Path:', 1)[1].split('Data Required Path:', 1)[0]
        data = arrival.split('tC2Q', 1)[-1].splitlines()[1:]
        fanout = [int(m.group(1)) for line in data if (m := re.search(r'\bt(?:INS|NET)\s+\w+\s+(\d+)\s+', line))]
        stats = re.search(r'Arrival Data Path Delay:\s*\(cell:\s*([\d.]+).*?route:\s*([\d.]+).*?tC2Q:\s*([\d.]+)', block, re.S)
        result.append((get(r'Slack\s*:\s*([\d.-]+)'), get(r'Logic Level:\s*(\d+)'),
                       *stats.groups(), max(fanout, default=0), get(r'From\s*:\s*(\S+)'), get(r'To\s*:\s*(\S+)')))
    assert len(result) == 10, 'Expected ten detailed setup paths'
    return result


def main():
    baseline = BOARD / 'sin12_r1_map2613_2026-10-27'
    experiment = ROOT / 'tmp/sin12_r1_replication/fpga/motor_bt_drive/impl/pnr'
    tr = (experiment / (NAME + '.tr')).read_text()
    cmd = (experiment / 'cmd.do').read_text()
    assert '-replicate' in cmd and '-route_option 2' in cmd and '-timing' in cmd
    assert '<Numbers of Setup Violated Endpoints>:0' in tr
    assert '<Numbers of Hold Violated Endpoints>:0' in tr
    fs = experiment / (NAME + '.fs')
    lines = ['# SIN12 资源复制对照实验（2026-10-27）', '',
             '仅在独立副本启用 `replicate_resources=1`；50 MHz、route_option=2、timing_driven=1 保持不变。',
             '实验 Tcl 与源文件校验清单位于 `tmp/sin12_r1_replication`；合格基线目录未覆盖。', '',
             '| 项目 | R1 基线 | 资源复制实验 |', '|---|---:|---:|',
             '| Fmax / MHz | 50.614 | 50.265 |', '| Setup 违例 | 0 | 0 |', '| Hold 违例 | 0 | 0 |',
             '| 最差 setup 裕量 / ns | +0.243 | +0.106 |',
             '| 布局布线总时长 | 3分56秒 | 3分23秒 |',
             '| Logic | 24935 | 24931 |', '| Register | 12829 | 13468 |', '| DSP | 15 | 15 |', '',
             '结论：复制实验缩短33秒，但寄存器增加639个，Fmax与setup裕量均下降。保留原R1作为当前候选，实验不替代基线，也未执行硬件下载。', '',
             '## 生效及文件核验', '',
             '- `impl/pnr/cmd.do` 实际包含 `-replicate`、`-route_option 2`、`-timing`；本次命令行未生成 process_config.json，不能声称从该文件核验。',
             '- Hold 报告出现 `gowin_replicate_reg_cur[0]_24`，证明网表中实际存在复制寄存器。',
             '- STA 时钟为 clk_50m / 20.000 ns；setup与hold TNS均0。',
             '- 实验 fs 时间：2026-10-27 23:13:01；PnR报告23:13:02，STA报告23:13:03（本机时间）。',
             '- 实验 fs SHA256：`' + hashlib.sha256(fs.read_bytes()).hexdigest().upper() + '`。', '',
             '## 前十条最差 setup 路径', '',
             'tCELL、tNET、tC2Q均取报告的Arrival Data Path统计（ns），不包含时钟树。Fanout为该数据路径各级输出的最大扇出，不含时钟树。', '']
    for label, source in [('R1基线', baseline), ('复制实验', experiment)]:
        lines += ['### ' + label, '', '| # | Slack | 逻辑级 | tCELL | tNET | tC2Q | 最大fanout | 起点 → 终点 |',
                  '|---:|---:|---:|---:|---:|---:|---:|---|']
        for i, row in enumerate(paths((source / (NAME + '.tr')).read_text()), 1):
            slack, level, cell, net, cq, fan, start, end = row
            lines.append(f'| {i} | {slack} | {level} | {cell} | {net} | {cq} | {fan} | `{start}` → `{end}` |')
        lines.append('')
    lines += ['## 后续优化依据', '',
              '复制实验最差路径为 yaw_error→neutral，19级逻辑，tNET=14.136 ns、tCELL=5.363 ns，走线占数据延迟约71%。不是单凭复制就能改善的情况。基线ToF数据到占用栅格写入路径也须结合扇出和组合级数优化。',
              '下一轮应分别评估导航内部条件寄存、owner选择逻辑与状态反馈路径，保持S0/硬停的直接关闭路径；每轮只改一项并重新验证50 MHz和功能。不能为通过时序放宽时钟。',
              'SIN12是系统导航版本名称，不是正弦计算模块；本轮关键路径没有DSP/BSRAM延迟主导的证据。', '',
              '复现：运行 `scripts/prepare_timing_replication_experiment.py` 生成独立副本，再由 Gowin gw_sh 执行副本中的 build_replication.tcl，完成后运行本脚本。准备脚本会更新实验副本，必须确认没有同目录构建在运行。',
              '相机 memory probe 是独立失败实验（RP0007）；此时序通过不表示相机已经并入统一位流。', '']
    out = BOARD / 'SIN12_TIMING_OPTIMIZATION_2026-10-27.md'
    out.write_text('\n'.join(lines), encoding='utf-8')
    print(out)


if __name__ == '__main__':
    main()
