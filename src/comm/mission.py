"""Actual FPGA mission telemetry. ID/state come from J frames, never local intent."""
import re

STATES = {0:'空闲', 1:'主动搜索', 2:'停留识别', 3:'目标对准', 4:'接近目标',
          5:'到达稳定确认', 6:'任务完成', 7:'扫描范围内未找到', 8:'运动许可超时',
          9:'视觉数据超时', 10:'传感器/近障/电机故障或距离过近',
          11:'旋转或任务总超时', 12:'任务取消', 13:'启动条件未满足', 14:'目标丢失或身份改变',
          15:'对准偏航超过8°，已停止', 16:'目标暂未确认，停车等待原目标恢复',
          17:'原目标短角度搜索'}
PATTERN = re.compile(r'J([01]) Q([0-9A-Fa-f]{8}) S([0-9A-Fa-f]{2})'
                     r' C([0-9A-Fa-f]{4}) K([0-9A-Fa-f]{8}) N([0-3])')


def parse_mission_status(line):
    match = PATTERN.fullmatch(line.strip())
    if not match:
        return None
    active, task_id, state, category, lock_id, leg = match.groups()
    state = int(state, 16)
    return dict(active=active=='1', task_id=int(task_id,16), state=state,
                state_name=STATES.get(state, '未知状态'), class_id=int(category,16),
                lock_id=int(lock_id,16), leg=int(leg))
