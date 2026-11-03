"""SIN12 goal-only wire contract; no wheel commands or host route in the frame."""
import re
import struct
from .protocol import build_frame

MAP_ID = 0x2613
STATE_NAMES = {0: '空闲', 1: 'FPGA规划中', 2: '等待规划', 3: '路点校正', 4: '航向闭环/左右扫描',
               6: '停稳采集新ToF', 7: '前进', 8: '停车测位', 9: '写入实测障碍',
               10: '切换扫描方向', 11: '到达并恢复初始航向', 12: '已停止/失败',
               13: '换算ToF推算障碍坐标', 14: '遇障停稳·重新确认测距与位姿',
               15: '固定左绕·逐格确认下一格'}
REASONS = {0: '无', 1: '运动许可超时', 2: '传感器失效', 3: '电机故障', 4: '近障硬停',
           5: '其他控制抢占/通信错误', 6: '启动参数或授权不符', 7: '无可达路径',
           8: '无新的稳定ToF帧', 9: '位置/编码器异常', 10: '总时限或分段时限',
           11: '重规划次数达到上限', 12: '人工停止', 13: '路点/终点超调超出容差，请核对位置后重启',
           14: '左绕下一格越界或已有障碍/禁行边，已停车'}
PATTERN = re.compile(r'N([01]) Q([0-9A-F]{4}) S([0-9A-F]{2}) E([0-9A-F]{2}) '
                     r'X([0-9A-F]{2}) Y([0-9A-F]{2}) G([0-9A-F]{2}) H([0-9A-F]{2}) '
                     r'R([0-9A-F]{2}) O([0-9A-F]{2}) P([0-9A-F]{2})')


def counts_per_cell_for_version(version):
    """Explicit contract: R16 provisional straight scale, old revisions unchanged."""
    if type(version) is int and version in (18,19,20):
        return 500
    if type(version) is int and version in (16,17):
        return 333
    if type(version) is int and 5 <= version <= 15:
        return 1000
    raise ValueError("需先收到已支持固件的新鲜K版本帧，不能猜测每格编码器计数")


def pack_autonav_goal(sequence, start, goal, counts_per_cell, tof_setback_mm,
                      geometry_confirmed=False, yaw_inverted=False, speed=12):
    for value in (*start, *goal):
        if type(value) is not int or not 0 <= value < 20:
            raise ValueError('起终点必须是0–19的整数格坐标')
    if len(start) != 2 or len(goal) != 2:
        raise ValueError('起终点需要X/Y两个坐标')
    if type(counts_per_cell) is not int or not 100 <= counts_per_cell <= 10000:
        raise ValueError('每格编码器计数必须为100–10000，且与固件编译参数一致')
    if type(tof_setback_mm) is not int or not -30 <= tof_setback_mm <= 50:
        raise ValueError('需实测ToF探测面退后量，当前支持-30至50mm')
    if not geometry_confirmed or type(speed) is not int or not 8 <= speed <= 12:
        raise ValueError('需确认几何/航向，速度为8–12')
    flags = 1 | (2 if yaw_inverted else 0)
    return build_frame(0x26, sequence, struct.pack('<HBBBBHhBB', MAP_ID, *start, *goal,
                       counts_per_cell, tof_setback_mm, flags, speed))


def parse_autonav_status(line):
    m = PATTERN.fullmatch(line)
    if m is None:
        return None
    active, *hexes = m.groups()
    seq, state_byte, reason, x, y, gx, gy, replans, ox, oy = (int(h, 16) for h in hexes)
    local_mode = bool(state_byte & 0x80)
    state = state_byte & 0x7F
    return dict(active=active == '1', sequence=seq, state=state, reason=reason,
                x=x, y=y, gx=gx, gy=gy, replans=replans, obstacle=(ox, oy),
                state_name=STATE_NAMES.get(state, '未知'), reason_name=REASONS.get(reason, '未知'), local_mode=local_mode)
