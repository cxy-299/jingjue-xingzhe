"""A4 task identity namespace, independent of COCO and OCR implementation."""
CLASS_BASE=0xA400
NAMES={CLASS_BASE+n:f'a4_digit_{n}' for n in range(10)}

def is_a4_category(name):
    return isinstance(name,str) and name in NAMES.values()

def target_label(name):
    return '数字 '+name[-1] if is_a4_category(name) else str(name)

def check_a4_identity(data):
    name=data.get('mission_class')
    if not is_a4_category(name): return
    if (data.get('mission_class_id')!=CLASS_BASE+int(name[-1]) or
        data.get('mission_color')!='any' or data.get('mission_strategy')!='a4_digits'):
        raise ValueError('A4数字身份/类别码/识别策略不一致，请重新读取Pi任务')

