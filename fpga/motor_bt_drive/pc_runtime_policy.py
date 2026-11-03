"""Read-only decisions for the console; these helpers never send motion."""


def confirmed_digit_follow_trigger(vision, received_at, now):
    """One current FPGA-confirmed digit can authorize a ToF handoff request.

    This returns trigger metadata only, never a claimed ToF object identity.
    Subsequent ToF following intentionally has no visual-presence dependency.
    """
    category=vision.get('class_id');token=vision.get('lock_id')
    if (not received_at or not 0<=now-received_at<=1.6 or
        vision.get('fresh') is not True or vision.get('visible') is not True or
        type(category) is not int or not 0xA400<=category<=0xA409 or
        type(token) is not int or not 0<token<=0xffffffff):
        return None
    return dict(digit=category-0xA400,class_id=category,lock_id=token)

def manual_avoid_status_text(status):
    """O is actual enable/state, not a firmware capability bit or command ACK."""
    states = {0: '待机', 1: '遇障停稳', 2: '请求板内局部规划', 3: '扫描/绕行执行',
              4: '绕行结束，等待新指令', 5: '已停止', 6: '绕行完成，检查前方后继续'}
    enabled = status['avoid_enabled']
    text = f"普通前进避障{'已启用' if enabled else '未启用'} · {states[status['state']]}"
    reasons = {1: '前进许可超时', 2: '人工停止/其他控制接管', 3: '传感器无效',
               4: '前方硬停', 5: '通信错误', 6: '规划启动/续行等待超时',
               7: '局部规划未成功', 8: '电机运动保护'}
    if status['reason']:
        text += f" · 原因码{status['reason']}：{reasons.get(status['reason'], '未知原因')}"
    if status['blocked_mask']:
        text += ' · 受阻保护已停机'
    if status['severe_mask']:
        text += ' · 反向/超速等异常，需排查'
    if not enabled:
        text += ' · 功能可用但未开启；上电/重配置后需停车启用，并等待板端确认'
    return text

def map_navigation_reply(status, request):
    """Validate map identity before interpreting any board completion/position.

    Local avoidance has its own temporary coordinates and must never satisfy a
    map goal. A host preview selection is not an accepted navigation request.
    """
    if not request or status.get('sequence') != request.get('sequence'):
        return 'unrelated'
    if status.get('local_mode'):
        return 'mode_mismatch'
    if (status.get('gx'), status.get('gy')) != tuple(request['goal']):
        return 'goal_mismatch'
    if status.get('active'):
        return 'active'
    if status.get('state') == 11 and status.get('reason') == 0:
        return ('arrived' if (status.get('x'), status.get('y')) == tuple(request['goal'])
                else 'invalid_completion')
    return 'stopped'


def navigation_obstacle_point(status, request, *, version, capability_fresh):
    """Return a board-projected cell only from the matching R19 map mission.

    N carries a held cell, not a new measurement on every UART transmission.
    R19 invalidates it when a new ray is pending/outside the field. Older images
    lack that guarantee and may also use a different physical odometry scale.
    Never reconstruct an obstacle from the current range, robot cell or goal:
    the board's stopped observation pose and heading belong to an earlier time.
    """
    if (not capability_fresh or version not in (19,20) or not request or
        request.get('version') != version or
        map_navigation_reply(status, request) in ('unrelated','mode_mismatch','goal_mismatch') or
        status.get('state') in (0,1,2,8,13,14) or not status.get('replans')):
        return None
    point=status.get('obstacle',())
    if len(point)!=2 or any(type(v) is not int or not 0<=v<20 for v in point):
        return None
    return tuple(point)

def continue_local_forward(previous, current, *, version, capability_fresh, held, mode, permitted):
    return (version >= 6 and capability_fresh and held == 'F' and mode == 'manual' and permitted
            and previous.get('local_mode') and current.get('local_mode')
            and previous.get('sequence') == current.get('sequence')
            and previous.get('active') and not current.get('active')
            and current.get('state') == 11 and current.get('reason') == 0)


def can_acknowledge_block(*, version, attempted, pending, fault_bits, blocked, severe,
                          fresh, command, speeds, idle, sensors_clear, evidence):
    """Only a stopped E1 episode may be acknowledged, once; no restart permission."""
    return bool(version >= 5 and not attempted and not pending and fault_bits & 0x10
                and blocked and not severe and fresh and command == 0 and len(speeds) == 4
                and all(abs(v) <= 1 for v in speeds) and idle and sensors_clear
                and all(evidence.get(w) == 1 for w in range(1, 5) if blocked & (1 << (w-1))))
