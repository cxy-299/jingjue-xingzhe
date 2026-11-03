"""Deterministic, clearly labelled demonstration. Never imports serial."""
import copy
import json
from pathlib import Path
from collections import deque

PROJECT = Path(__file__).resolve().parents[3]


def shortest_path(occupied, start, goal):
    blocked = set(occupied)
    start, goal = tuple(start), tuple(goal)
    if start[1]*20+start[0] in blocked or goal[1]*20+goal[0] in blocked:
        return []
    todo = deque([start]); parents = {start: None}
    while todo:
        cell = todo.popleft()
        if cell == goal:
            route = []
            while cell is not None:
                route.append(list(cell)); cell = parents[cell]
            return route[::-1]
        for dx, dy in [(0,1),(-1,0),(0,-1),(1,0)]:
            nxt = cell[0]+dx, cell[1]+dy
            if (0 <= nxt[0] < 20 and 0 <= nxt[1] < 20 and nxt not in parents
                    and nxt[1]*20+nxt[0] not in blocked):
                parents[nxt] = cell; todo.append(nxt)
    return []


def map_spec():
    spec = json.loads((PROJECT/'config/nav-map-sin12.json').read_text(encoding='utf-8'))
    # Retain the project's actual preview inflation algorithm where available.
    import sys
    if str(PROJECT) not in sys.path: sys.path.insert(0, str(PROJECT))
    from scripts.build_nav_map import occupied_cells
    return spec, [i for i,v in enumerate(occupied_cells(spec)) if v]


class DemoBackend:
    def __init__(self, clock=None):
        import time
        self.clock = clock or time.monotonic
        spec, occupied = map_spec()
        self.data = {'demo': True, 'name': '境觉行者', 'connected': True,
                     'desktop_enabled': True, 'firmware': 'R20 / K14 · 演示',
                     'mode': 'manual', 'direction': 'S', 'speed': 12,
                     'sensors': {'distance_mm':854,'yaw_deg':0,'imu_valid':True,'tof_valid':True,'fault':0},
                     'wheels': {'targets':[0]*4,'speeds':[0]*4,'duties':[0]*4},
                     'map': {'size':20,'occupied':occupied,'start':spec['start_cell'],
                             'current':spec['start_cell'],'goal':[17,17],'route':[], 'measured':[], 'pose_confirmed':True},
                     'tasks': {'status':'演示待机','mission_id':100,'digit':7,'arrival_mm':200,'active':False},
                     'vision': {'online':True,'digit':7,'confirmed':True,'fps':20,'detector_ms':16.6,
                                'model':'Printed Digit v4 · 演示','message':'模拟数字7，未连接相机'},
                     'detail':'本模式不打开串口，不向真实机器人发送指令'}
        self.route_index = 0; self.last_step = self.clock(); self.stops = 0

    def ready(self):
        return True, '演示模式'

    def snapshot(self): return copy.deepcopy(self.data)

    def handle(self, name, p):
        d = self.data
        if name in {'stop','manual.release'}:
            self.stops += 1; d['direction']='S';d['tasks']['active']=False;d['tasks']['status']='已停止 · 演示'
        elif name == 'manual.move':
            if p.get('direction') not in ['F','B','L','R']: raise ValueError('方向必须为F/B/L/R')
            d['mode']='manual';d['direction']=p['direction']
        elif name == 'manual.speed':
            value=p.get('value')
            if value not in [12,16,20]:raise ValueError('档位必须为12/16/20')
            self.handle('stop',{});d['speed']=value
        elif name == 'nav.preview':
            goal = p.get('goal')
            if not isinstance(goal,list) or len(goal)!=2 or any(type(x) is not int or not 0<=x<20 for x in goal):raise ValueError('终点越界')
            route=shortest_path(d['map']['occupied'], d['map']['current'],goal)
            if not route:raise ValueError('终点不可达或位于安全区')
            d['map'].update(goal=goal,route=route)
        elif name == 'nav.pose':
            pos=p.get('position')
            if not isinstance(pos,list) or len(pos)!=2 or any(type(x) is not int or not 0<=x<20 for x in pos):raise ValueError('当前位置越界')
            if pos[1]*20+pos[0] in d['map']['occupied']:raise ValueError('当前位置在安全区内')
            d['map'].update(current=pos,start=pos,route=[],pose_confirmed=True)
        elif name == 'nav.start':
            if not d['map']['route']:raise ValueError('先选择可达终点')
            d['mode']='autonav';d['tasks'].update(active=True,status='演示逐格导航');self.route_index=0
        elif name in {'vision.prepare','vision.search','vision.lock'}:
            digit=p.get('digit',7);arrival=p.get('arrival_mm',200)
            if type(digit) is not int or not 0<=digit<=9:raise ValueError('数字范围0至9')
            if type(arrival) is not int or not 180<=arrival<=1000:raise ValueError('距离范围180至1000mm')
            d['vision'].update(digit=digit,confirmed=True)
            d['tasks'].update(mission_id=d['tasks']['mission_id']+1,digit=digit,arrival_mm=arrival,status='新任务已准备 · 演示')
        elif name == 'task.read':d['tasks']['status']='已读取演示任务，等待明确启动'
        elif name == 'task.start':d['mode']='mission';d['tasks'].update(active=True,status='两阶段接近 · 演示')
        elif name in {'follow.start','follow.digit'}:d['mode']='follow';d['tasks'].update(active=True,status='ToF保持200mm · 演示')
        elif name == 'turn.start':
            if p.get('direction') not in ['left','right']:raise ValueError('方向错误')
            d['sensors']['yaw_deg']+=(90 if p['direction']=='left' else -90);d['tasks']['status']='转角完成 · 演示'
        elif name in {'avoid.enable','avoid.disable'}:d['detail']='前进避障'+('开启' if name.endswith('enable') else '关闭')+' · 演示'
        elif name == 'pid.set':d['detail']='PID参数仅在演示内记录'
        else:raise ValueError('演示后端不支持此操作')
        return {'message':d['tasks']['status'] if name!='manual.move' else '演示方向 '+d['direction']}

    def tick(self):
        d=self.data;now=self.clock()
        if d['tasks']['active'] and d['mode']=='autonav' and now-self.last_step>=.5:
            self.last_step=now;self.route_index+=1
            route=d['map']['route']
            if self.route_index<len(route):d['map']['current']=route[self.route_index]
            else:d['tasks'].update(active=False,status='到达演示终点');d['direction']='S'
        moving=d['direction']!='S'
        v=d['speed'] if moving else 0
        d['wheels'].update(targets=[v]*4,speeds=[v]*4,duties=[v*30]*4)
