"""Check live Pi perception before authorizing a hardware mission."""
from src.core.a4_targets import check_a4_identity


def check_mission_readiness(data, allow_search=False):
    check_a4_identity(data)
    if not data.get('online') or data.get('task_mode') != 'mission':
        raise ValueError('Pi未在线或尚未准备语义任务')
    age = data.get('mission_perception_tx_age_ms')
    if (data.get('mission_perception_tx_id') != data.get('mission_id')
            or age is None or age > 1200):
        raise ValueError('新任务尚无新鲜USB感知帧，稍候再读取')
    if (data.get('task_lock_id') and data.get('task_target_locked')
            and data.get('task_target_confirmed')):
        return '画内目标已确认：可对准并接近'
    if data.get('task_lock_id'):
        raise ValueError('已选目标暂不可见或仍在确认；请等待原目标恢复，不启动扫描')
    count = data.get('mission_candidate_count')
    if count is None:
        count = sum(d.get('class_name') == data.get('mission_class')
                    and d.get('confidence', 0) >= .5
                    for d in data.get('detections', []))
    if count > 1:
        raise ValueError(f'检测到{count}个候选；请在Pi点选具体物体，并使用所选物体准备新任务')
    if count == 1:
        raise ValueError('候选目标尚未连续确认；请保持可见，待Pi显示锁定编号后再读取')
    if not allow_search:
        raise ValueError('画内尚无确认目标；离地接近测试请先放入目标。画外搜索需勾选搜索且底盘实际可转动')
    return '画外搜索：需底盘真实转动；固定离地只能验证搜索超时停车'
