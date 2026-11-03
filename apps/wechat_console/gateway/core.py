"""Single-owner command policy, independent of serial ports and HTTP threads."""
from collections import deque
import copy
import secrets
import time


class Rejected(Exception):
    def __init__(self, message, status=409):
        super().__init__(message)
        self.status = status


class ControlCore:
    LEASE_MS = 400
    MAX_COMMAND_FUTURE_MS = 800
    PASSIVE = {'nav.preview', 'nav.pose', 'task.read', 'vision.prepare', 'vision.search', 'vision.lock'}
    ACTIONS = PASSIVE | {'manual.move', 'manual.release', 'manual.speed', 'nav.start',
                         'task.start', 'follow.start', 'follow.digit', 'turn.start',
                         'avoid.enable', 'avoid.disable', 'pid.set'}

    def __init__(self, backend, clock=None, now_ms=None):
        self.backend = backend
        self.clock = clock or time.monotonic
        self.now_ms = now_ms or (lambda: int(time.time() * 1000))
        self.session = None
        self.last_seq = -1
        self.armed = False
        self.expires = 0.0
        self.reason = '等待手机连接'
        self.in_backend = False
        self.events = deque(maxlen=30)

    def _call(self, name, payload=None):
        self.in_backend = True
        try:
            return self.backend.handle(name, payload or {})
        finally:
            self.in_backend = False

    def revoke(self, reason, stop=True):
        was_armed = self.armed
        self.armed = False
        self.expires = 0.0
        self.reason = reason
        self.events.appendleft({'at': self.now_ms(), 'message': reason})
        if stop:
            self._call('stop', {'reason': reason})
        return was_armed

    def local_stop(self, reason='电脑本地停止或接管'):
        if not self.in_backend:
            self.revoke(reason, stop=False)

    def open_session(self, label):
        self.revoke('建立新会话，等待明确授权')
        self.session = secrets.token_urlsafe(24)
        self.last_seq = -1
        return {'session_id': self.session, 'server_time_ms': self.now_ms(), 'lease_ms': self.LEASE_MS}

    def _check(self, data):
        if not self.session or data.get('session_id') != self.session:
            raise Rejected('会话已失效，请重新连接', 401)
        seq = data.get('seq')
        if type(seq) is not int or seq <= self.last_seq or seq > 2**53 - 1:
            raise Rejected('重复或过期指令')
        deadline = data.get('deadline_ms')
        now = self.now_ms()
        if type(deadline) is not int or not now <= deadline <= now + self.MAX_COMMAND_FUTURE_MS:
            raise Rejected('指令已超时，请重新操作')
        self.last_seq = seq

    def action(self, data):
        self.tick()
        self._check(data)
        name = data.get('action')
        payload = data.get('payload', {})
        if not isinstance(payload, dict):
            raise Rejected('参数格式错误', 400)
        if name == 'stop':
            self.revoke('手机停止S')
        elif name == 'arm':
            ready, reason = self.backend.ready()
            if not ready:
                raise Rejected(reason)
            self.armed = True
            self.expires = self.clock() + self.LEASE_MS / 1000
            self.reason = '本次手机控制已启用'
        elif name == 'heartbeat':
            if not self.armed:
                raise Rejected('许可已撤销，需重新明确启用')
            self.expires = self.clock() + self.LEASE_MS / 1000
        elif name in self.ACTIONS:
            if name not in self.PASSIVE and not self.armed:
                raise Rejected('请先启用本次手机控制')
            if name in {'vision.prepare', 'vision.search', 'vision.lock', 'task.read', 'nav.pose', 'pid.set'}:
                self.revoke('停车后更新任务参数')
            ready, reason = self.backend.ready()
            if name not in self.PASSIVE and not ready:
                self.revoke(reason)
                raise Rejected(reason)
            result = self._call(name, payload)
            self.events.appendleft({'at': self.now_ms(), 'message': name})
            return {'accepted': True, 'result': result, 'state': self.snapshot()}
        else:
            raise Rejected('不支持的操作', 400)
        return {'accepted': True, 'state': self.snapshot()}

    def tick(self):
        if self.armed:
            ready, reason = self.backend.ready()
            if self.clock() >= self.expires:
                self.revoke('手机许可超时，已停车')
            elif not ready:
                self.revoke(reason)
        self.backend.tick()

    def snapshot(self):
        result = copy.deepcopy(self.backend.snapshot())
        result.update(server_time_ms=self.now_ms(), remote={
            'armed': self.armed, 'reason': self.reason,
            'lease_ms': max(0, int((self.expires - self.clock()) * 1000)) if self.armed else 0,
            'connected': bool(self.session), 'events': list(self.events),
        })
        return result
