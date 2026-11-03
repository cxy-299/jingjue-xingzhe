import argparse
import base64
import json
import math
import re
import socket
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import cv2

from src.camera.factory import create_camera
from src.comm.protocol import pack_heartbeat, pack_nav_path, pack_locked_target, pack_mission_observation
from src.comm.mission import parse_mission_status
from src.comm.transport import TransportHub
from src.config import load_config
from src.core.messages import TargetObservation
from src.core.visual_alignment import VisualAlignmentController
from src.detection.target_selector import TargetSelector
from src.detection.factory import create_detector
from src.core.a4_targets import is_a4_category
from src.detection.locked_target import LockedTarget
from src.detection.semantic_mission import SemanticMission
from src.detection.mission_geometry import MissionGeometryReporter
from src.comm.protocol import pack_visual_primary_observation
from src.detection.red_bottle import red_coverage
from scripts.build_nav_map import load_map, occupied_cells, shortest_path_from


SENSOR_LINE = re.compile(
    r"I([01]) T([01]) D(\d{4}) H([01])"
    r"(?: F([0-9A-Fa-f]{2}) R([0-9A-Fa-f]{8})"
    r" P([0-9A-Fa-f]{8}) Y([0-9A-Fa-f]{8})"
    r"(?: W([0-9A-Fa-f]))?)?"
)


def parse_sensor_line(line):
    match = SENSOR_LINE.fullmatch(line.strip())
    if not match:
        return None
    imu_ok, tof_ok, distance, hard_stop, faults, roll, pitch, yaw, wheel_fault = match.groups()
    result = {
        "imu_valid": imu_ok == "1", "tof_valid": tof_ok == "1",
        "distance_mm": int(distance), "hard_stop": hard_stop == "1",
        "faults": faults or "00", "wheel_fault": wheel_fault or "0",
    }
    if roll and pitch and yaw:
        angles = [math.degrees(struct.unpack(">f", bytes.fromhex(v))[0])
                  for v in (roll, pitch, yaw)]
        if all(math.isfinite(v) and abs(v) <= 360 for v in angles):
            result.update(roll_deg=angles[0], pitch_deg=angles[1], yaw_deg=angles[2])
    return result


class DashboardState:
    def __init__(self, goal_ttl_s=2.0, clock=time.monotonic):
        self.condition = threading.Condition()
        self.jpeg = None
        self.raw_frame = None
        self.raw_metadata = None
        self.frame_version = 0
        self.pending_nav_goal = None
        self.pending_nav_goal_at = None
        self.goal_ttl_s = float(goal_ttl_s)
        self.clock = clock
        self.nav_goal_in_flight = False
        self.nav_status = {
            "nav_goal_tx_enabled": False,
            "nav_goal_state": "默认锁定：可在地图上预览；FPGA 断电时不要下发",
            "nav_goal_last_sent": None,
            "nav_goal_pending": False,
            "nav_goal_last_seq": None,
        }
        self.task_status = {
            "task_mode": "observe",
            "task_target_class": "",
            "task_target_locked": False,
            "task_target_confirmed": False,
            "task_lock_retained": False,
            "task_reacquiring": False,
            "task_state": "视觉观察模式：未锁定目标",
            "task_actuator": "未启用",
            "task_lock_id": 0,
            "task_class_id": 65535,
        }
        self.tracker = LockedTarget()
        self.mission = SemanticMission()
        self.model_classes = {}
        self.detection_choices = {}
        self.choice_red_ratios = {}
        self.choice_sequence = 0
        self.current_choice_ids = set()
        self.lock_sequence = 0
        self.task_revision = 0
        self.status = {
            "online": False,
            "message": "正在启动视觉服务",
            "detections": [],
            **self.task_status,
            "fpga_imu_valid": False,
            "fpga_tof_valid": False,
            "fpga_distance_mm": None,
            "fpga_hard_stop": False,
            "fpga_roll_deg": None,
            "fpga_pitch_deg": None,
            "fpga_yaw_deg": None,
            "fpga_faults": "00",
            "fpga_wheel_fault": "0",
        }

    def update(self, jpeg, status, raw_frame=None):
        with self.condition:
            self.jpeg = jpeg
            # Retain the same inference frame, before any drawing. No second
            # camera, no detector-generated training labels, no disk I/O here.
            self.raw_frame = raw_frame.copy() if raw_frame is not None else None
            self.raw_metadata = {k: status.get(k) for k in (
                'frame_id', 'frame_captured_unix_s', 'resolution', 'model',
                'detections', 'alignment_center_target', 'alignment_aim_y_target',
                'fpga_distance_mm', 'fpga_tof_valid', 'fpga_sensor_age_ms',
                'detector_backend', 'detector_revision', 'a4_pages', 'task_target_visibility')}
            self.status = {**self.status, **status, **self.nav_status, **self.task_status}
            self.frame_version += 1
            self.condition.notify_all()

    def update_status(self, **values):
        with self.condition:
            self.status = {**self.status, **values}
            self.condition.notify_all()

    def set_task_mode(self, mode, target_class="", detection_id=None):
        with self.condition:
            choice = self.detection_choices.get(detection_id)
            if (choice is not None and is_a4_category(choice[0].class_name)
                    and choice[0].source not in ('a4_digit_template','printed_digit_template')):
                raise ValueError('新数字锁定须看到当前完整可读的数字；不使用残缺字符猜测')
            self.mission.clear()
            self.task_status.update(self.mission.snapshot())
            if mode == "observe":
                self.tracker.clear()
                self.task_status.update(task_lock_id=0, task_class_id=65535)
            elif detection_id is not None:
                choice = self.detection_choices.get(detection_id)
                if (choice is None or detection_id not in self.current_choice_ids
                        or self.clock() - choice[1] > 2.0):
                    raise ValueError("所选目标已离开或当前画面已过期，请重新点选可见目标")
                detection = choice[0]
                target_class = detection.class_name
                self.lock_sequence = (self.lock_sequence + 1) & 0xFFFFFFFF or 1
                self.tracker.lock(detection, self.lock_sequence, self.clock(), choice[2])
                self.task_status.update(task_lock_id=self.lock_sequence,
                                        task_class_id=detection.class_id)
            elif mode == "follow":
                if self.tracker.detection is None or self.tracker.missing:
                    raise ValueError("先点击画面中具体目标，再启动跟随")
                target_class = self.tracker.detection.class_name
            else:
                self.tracker.clear()
                self.task_status.update(task_lock_id=0, task_class_id=65535)
            self.task_revision += 1
            self.task_status.update(
                task_mode=mode,
                task_target_class=target_class,
                task_target_locked=False,
                task_target_confirmed=False,
                task_lock_retained=bool(self.tracker.token),
                task_reacquiring=bool(self.tracker.token),
                task_state=(
                    f"已锁定目标类别：{target_class}，等待识别"
                    if target_class else "视觉观察模式：未锁定目标"
                ),
            )
            self.status.update(self.task_status)
            self.condition.notify_all()

    def prepare_mission(self, category, color='any', distance_mm=200, detection_id=None):
        with self.condition:
            supported = {str(name):int(cid) for cid,name in self.model_classes.items()}
            if category not in supported:
                raise ValueError('当前模型不支持该类别；请使用识别列表中的英文类别')
            choice = None
            if detection_id is not None:
                choice = self.detection_choices.get(detection_id)
                if (choice is None or detection_id not in self.current_choice_ids
                        or self.clock() - choice[1] > 2.0):
                    raise ValueError('所选目标已离开，请重新点选可见物体')
                if choice[0].class_name != category or choice[0].confidence < .50:
                    raise ValueError('所选物体类别或置信度不符合任务，请重新选择')
                if is_a4_category(category) and choice[0].source not in ('a4_digit_template','printed_digit_template'):
                    raise ValueError('新数字任务须看到当前完整可读的数字；纸张四边不作要求')
                if color == 'red' and self.choice_red_ratios.get(detection_id, 0) < .15:
                    raise ValueError('所选物体未通过红色筛选，请选红色目标或改为不限颜色')
            self.mission.prepare(category, color, distance_mm)
            self.tracker.clear()
            if choice is not None:
                self.lock_sequence = (self.lock_sequence + 1) & 0xffffffff or 1
                self.tracker.lock(choice[0], self.lock_sequence, self.clock(), choice[2])
            self.task_revision += 1
            self.task_status.update(self.mission.snapshot(), task_mode='mission',
                mission_class_id=supported[category], mission_fpga=None,
                mission_candidate_count=0, mission_selection='manual' if choice else 'automatic',
                mission_ready=False,
                task_target_class=category, task_lock_id=self.tracker.token, task_class_id=supported[category],
                task_target_locked=False, task_target_confirmed=False,
                task_lock_retained=bool(self.tracker.token), task_reacquiring=bool(self.tracker.token),
                task_state='语义任务已准备；请在驾驶台读取任务并明确启动，网页不会自行开车')
            self.status.update(self.task_status)
            return dict(self.task_status)

    def associate_choices(self, detections, appearances, now):
        """Stable selection handles while an object stays uniquely visible.

        Refresh the detection behind a handle, not the handle's creation time.
        Mutual unique matching prevents one old choice from selecting two boxes.
        """
        old = {key:value for key,value in self.detection_choices.items()
               if now-value[1] <= 2.0}
        by_old, by_new = {}, {}
        for key,(previous,_,feature) in old.items():
            for index,(d,appearance) in enumerate(zip(detections,appearances)):
                score = LockedTarget.score(previous,d)
                distance = LockedTarget.appearance_distance(feature,appearance)
                if score is None or (distance is not None and distance > .65):
                    continue
                rank = score-.25*(distance or 0)
                by_old.setdefault(key,[]).append((rank,index))
                by_new.setdefault(index,[]).append((rank,key))
        for candidates in [*by_old.values(),*by_new.values()]:
            candidates.sort(key=lambda item:item[0],reverse=True)
        keys = []
        for index in range(len(detections)):
            candidates = by_new.get(index,[])
            key = None
            if candidates and (len(candidates)==1 or candidates[0][0]-candidates[1][0]>=.10):
                proposed = candidates[0][1]
                reverse = by_old[proposed]
                if reverse[0][1]==index and (len(reverse)==1 or reverse[0][0]-reverse[1][0]>=.10):
                    key = proposed
            if key is None:
                self.choice_sequence += 1
                key = f"d{self.choice_sequence}"
            keys.append(key)
        # Only latest handles remain selectable; disappeared handles cannot be
        # refreshed by a different object after a long confirmation delay.
        self.detection_choices = {key:(d,now,appearance)
            for key,d,appearance in zip(keys,detections,appearances)}
        self.current_choice_ids = set(keys)
        return keys

    def process_detections(self, detections, frame_id, frame=None):
        with self.condition:
            now = self.clock()
            rows = []
            appearances = [LockedTarget.appearance(frame, d) for d in detections]
            keys = self.associate_choices(detections, appearances, now)
            self.choice_red_ratios = {key: (red_coverage(frame, d) if frame is not None else 0)
                                     for key, d in zip(keys, detections)}
            for index, d in enumerate(detections):
                key = keys[index]
                rows.append(dict(detection_id=key, class_id=d.class_id,
                                 class_name=d.class_name, confidence=round(d.confidence, 3),
                                 source=d.source,
                                 visibility=('current_intact_digit' if d.source=='printed_digit_template'
                                             else 'partial_paper_intact_digit' if d.source=='a4_partial_digit'
                                             else 'full_page' if d.source=='a4_digit_template' else 'model_box'),
                                 cx=round(d.cx_px), cy=round(d.cy_px),
                                 bbox=[d.x1, d.y1, d.x2, d.y2],
                                 frame_width=d.frame_width, frame_height=d.frame_height))
            mode = self.task_status['task_mode']
            category = self.task_status['task_target_class']
            semantic_reason = ''
            if mode == 'mission' and not self.tracker.token:
                candidate, semantic_reason = self.mission.candidate_for(detections, frame, now)
                if candidate is not None:
                    self.lock_sequence = (self.lock_sequence + 1) & 0xffffffff or 1
                    appearance = LockedTarget.appearance(frame, candidate)
                    self.tracker.lock(candidate, self.lock_sequence, now, appearance)
                    self.task_status.update(task_lock_id=self.lock_sequence,
                                            task_class_id=candidate.class_id)
            # Category search discovers candidates. Only a concrete user click locks identity.
            target = self.tracker.update(detections, now, appearances) if self.tracker.token else None
            visible = target is not None
            self.task_status['task_target_visibility'] = (
                'current_intact_digit' if visible and target.source=='printed_digit_template'
                else 'partial_paper_intact_digit' if visible and target.source=='a4_partial_digit'
                else 'full_page' if visible and target.source=='a4_digit_template'
                else 'model_box' if visible else 'not_confirmed')
            self.task_status['task_target_locked'] = visible
            self.task_status['task_target_confirmed'] = visible and self.tracker.hits >= 2
            self.task_status['task_lock_retained'] = bool(self.tracker.token)
            self.task_status['task_reacquiring'] = bool(self.tracker.token and not visible)
            self.task_status['task_match_reason'] = self.tracker.match_reason
            self.task_status['task_candidate_count'] = self.tracker.candidate_count
            self.task_status['task_match_distance'] = self.tracker.best_distance
            reason = {
                'ambiguous': '相似目标不唯一，等待区分',
                'appearance': '同类目标已检测到，但外观尚未匹配；保留原锁定',
                'confirming': f'正在确认返回目标 {self.tracker.reacquire_hits}/{self.tracker.reacquire_required} 帧',
                'not_visible': '目标暂离画面，等待原目标返回',
            }.get(self.tracker.match_reason, '等待目标确认')
            if self.tracker.token:
                self.task_status['task_state'] = (
                    f"已锁定 {category} #{self.tracker.token}，{'跟随意图已开启' if mode == 'follow' else '仅锁定观察'}"
                    if visible else f"保留锁定 {category} #{self.tracker.token}："
                    + reason)
            else:
                count = sum(d.class_name == category for d in detections)
                self.task_status['task_state'] = (
                    f"找到 {count} 个 {category}，请点选其中一个" if mode == 'search' and count
                    else f"搜索 {category}：未找到" if mode == 'search'
                    else "观察全部类别；点击画面或列表选择具体目标")
            for d, row in zip(detections, rows):
                row['selected'] = d is target
            if mode == 'mission':
                self.task_status.update(self.mission.snapshot())
                self.task_status['mission_candidate_count'] = sum(
                    d.class_name == category and d.confidence >= .50
                    and (self.mission.color == 'any' or self.choice_red_ratios[key] >= .15)
                    for key, d in zip(keys, detections))
                self.task_status['mission_ready'] = bool(visible and self.tracker.hits >= 2)
                self.task_status['task_state'] = (f'语义锁定 {category} #{self.tracker.token}'
                    if visible else semantic_reason or '原任务/数字身份已保留；停车持续识别，找回后由支持恢复的FPGA自动续行')
            return target, rows, dict(self.task_status), self.task_revision

    def queue_nav_goal(self, x, y):
        with self.condition:
            self._expire_nav_goal_locked()
            # 单槽队列不覆盖上一条尚未写出的目标，避免界面连点导致误发。
            if self.pending_nav_goal is not None or self.nav_goal_in_flight:
                return False
            self.pending_nav_goal = (x, y)
            self.pending_nav_goal_at = self.clock()
            self.nav_status["nav_goal_state"] = f"待发送：格 ({x}, {y})"
            self.nav_status["nav_goal_pending"] = True
            self.status.update(self.nav_status)
            return True

    def take_nav_goal(self):
        with self.condition:
            self._expire_nav_goal_locked()
            goal = self.pending_nav_goal
            self.pending_nav_goal = None
            self.pending_nav_goal_at = None
            if goal is not None:
                self.nav_goal_in_flight = True
            return goal

    def _expire_nav_goal_locked(self):
        # 相机/推理阻塞时不能无限积压目标；恢复后也不能迟发旧目标。调用者持有锁。
        if (self.pending_nav_goal_at is not None and
                self.clock() - self.pending_nav_goal_at >= self.goal_ttl_s):
            self.pending_nav_goal = None
            self.pending_nav_goal_at = None
            self.nav_status["nav_goal_pending"] = False
            self.nav_status["nav_goal_state"] = "目标排队超时，已丢弃；请检查相机/推理后重新发送"
            self.status.update(self.nav_status)

    def status_snapshot(self):
        with self.condition:
            self._expire_nav_goal_locked()
            result = dict(self.status)
            actual_at = self.task_status.get('mission_fpga_received_at')
            result['mission_fpga_age_ms'] = (None if actual_at is None else
                max(0, round((time.monotonic()-actual_at)*1000)))
            sent_at = self.task_status.get('mission_perception_tx_at')
            result['mission_perception_tx_age_ms'] = (None if sent_at is None else
                max(0, round((time.monotonic()-sent_at)*1000)))
            return result

    def nav_sent(self, x, y, ok, sequence=None, steps=None):
        with self.condition:
            self.nav_goal_in_flight = False
            detail = f"；路径 {steps} 步" if steps is not None else ""
            self.nav_status["nav_goal_state"] = (
                f"已写入树莓派 USB 串口：格 ({x}, {y}){detail}；FPGA 未回传确认"
                if ok else "串口写入失败：目标已丢弃，请检查连接后重新发送"
            )
            if ok:
                self.nav_status["nav_goal_last_sent"] = [x, y]
                self.nav_status["nav_goal_last_seq"] = sequence
            self.nav_status["nav_goal_pending"] = False
            self.status.update(self.nav_status)


def navigation_settings(cfg):
    """导航配置错误时锁住下发并显示原因，视觉服务仍可运行。"""
    nav = cfg.get("navigation", {})
    error = ""
    if not isinstance(nav, dict):
        error = "navigation 应为 YAML 小节，请检查缩进和冒号后的空格"
    elif type(nav.get("goal_tx_enabled", False)) is not bool:
        error = "goal_tx_enabled 必须为 true/false，不能是带引号的字符串"
    elif not isinstance(nav.get("control_token", ""), str):
        error = "control_token 必须为字符串"
    if error:
        return False, "", f"导航配置错误，已锁定：{error}"
    token = nav.get("control_token", "")
    enabled = nav.get("goal_tx_enabled", False) and bool(token.strip())
    if nav.get("goal_tx_enabled", False) and not token.strip():
        return False, "", "导航配置错误，已锁定：启用下发时必须设置非空 control_token"
    return enabled, token, ""


def route_direction_codes(route):
    """Convert adjacent map cells to the SIN6/SIN7 route byte codes."""
    mapping = {(0, 1): 0, (0, -1): 1, (-1, 0): 2, (1, 0): 3}
    codes = []
    for (x0, y0), (x1, y1) in zip(route, route[1:]):
        try:
            codes.append(mapping[(x1 - x0, y1 - y0)])
        except KeyError as exc:
            raise ValueError("路径必须由相邻地图格组成") from exc
    if len(codes) > 64:
        raise ValueError("FPGA 路径最多 64 步")
    return codes


def make_handler(state, html_path, nav_map_payload=None, nav_goal_enabled=False, nav_token=""):
    class DashboardHandler(BaseHTTPRequestHandler):
        def send_json(self, code, payload):
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/":
                body = html_path.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/a4-targets.html":
                body=(Path(html_path).parent/"a4-targets.html").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type","text/html; charset=utf-8")
                self.send_header("Content-Length",str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/api/status":
                self.send_json(200, state.status_snapshot())
                return

            if path == "/api/nav/map" and nav_map_payload is not None:
                self.send_json(200, nav_map_payload)
                return

            if path == "/health":
                body = b"ok\n"
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/snapshot.jpg":
                with state.condition:
                    body = state.jpeg
                if body is None:
                    self.send_error(503, "Frame not ready")
                    return
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/snapshot-raw.jpg":
                with state.condition:
                    raw, metadata = state.raw_frame, state.raw_metadata
                if raw is None:
                    self.send_error(503, "Raw frame not ready")
                    return
                ok, encoded = cv2.imencode('.jpg', raw, [cv2.IMWRITE_JPEG_QUALITY, 95])
                if not ok:
                    self.send_error(503, "Raw frame encoding failed")
                    return
                body = encoded.tobytes()
                self.send_response(200)
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Vision-Metadata', base64.b64encode(
                    json.dumps(metadata, ensure_ascii=True).encode()).decode())
                self.end_headers()
                self.wfile.write(body)
                return

            if path == "/stream.mjpg":
                self.send_response(200)
                self.send_header(
                    "Content-Type",
                    "multipart/x-mixed-replace; boundary=frame",
                )
                self.send_header("Cache-Control", "no-store, no-cache")
                self.end_headers()
                version = -1
                try:
                    while True:
                        with state.condition:
                            state.condition.wait_for(
                                lambda: (
                                    state.frame_version != version
                                    and state.jpeg is not None
                                ),
                                timeout=5.0,
                            )
                            jpeg = state.jpeg
                            version = state.frame_version
                        if jpeg is None:
                            continue
                        self.wfile.write(b"--frame\r\n")
                        self.wfile.write(b"Content-Type: image/jpeg\r\n")
                        self.wfile.write(
                            f"Content-Length: {len(jpeg)}\r\n\r\n".encode()
                        )
                        self.wfile.write(jpeg)
                        self.wfile.write(b"\r\n")
                except (BrokenPipeError, ConnectionResetError):
                    pass
                return

            self.send_error(404)

        def do_POST(self):
            path = self.path.split("?", 1)[0]
            if path == '/api/mission/prepare':
                try:
                    length = int(self.headers.get('Content-Length', '0'))
                    if not 1 <= length <= 1024 or self.headers.get('Content-Type','').split(';')[0] != 'application/json':
                        raise ValueError('仅接受1–1024字节JSON')
                    request = json.loads(self.rfile.read(length))
                    result = state.prepare_mission(request.get('target_class'),
                        request.get('color','any'), request.get('distance_mm',200),
                        request.get('detection_id'))
                except (ValueError, TypeError, KeyError) as error:
                    self.send_json(400, {'error':str(error)})
                    return
                self.send_json(202, result)
                return
            if path == "/api/task/mode":
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                    if not 1 <= length <= 1024:
                        raise ValueError("请求长度错误")
                    if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
                        raise ValueError("仅接受 JSON")
                    request = json.loads(self.rfile.read(length))
                    mode = request.get("mode", "observe")
                    target_class = request.get("target_class", "")
                    if mode not in ("observe", "search", "follow"):
                        raise ValueError("任务模式必须为 observe/search/follow")
                    if not isinstance(target_class, str) or len(target_class) > 32:
                        raise ValueError("目标类别不合法")
                    if mode != "observe" and not target_class:
                        raise ValueError("搜索或跟随模式必须先锁定目标类别")
                    state.set_task_mode(mode, target_class, request.get('detection_id'))
                except (ValueError, TypeError, KeyError, json.JSONDecodeError) as error:
                    self.send_json(400, {"error": str(error)})
                    return
                self.send_json(202, {
                    "state": "accepted", "mode": mode,
                    "target_class": target_class,
                    "note": "树莓派发送锁定目标帧；车辆是否执行以 FPGA 蓝牙回传为准",
                })
                return
            if path != "/api/nav/goal":
                self.send_error(404)
                return
            # 当前实际板载位流不具备运动控制；默认强制锁住目标下发。
            if not nav_goal_enabled:
                self.send_json(423, {"error": "导航目标下发未启用，不能启动小车"})
                return
            if not nav_token or self.headers.get("X-Nav-Token", "") != nav_token:
                self.send_json(403, {"error": "导航控制口令不正确"})
                return
            if self.headers.get("Content-Type", "").split(";", 1)[0] != "application/json":
                self.send_json(415, {"error": "仅接受 JSON"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 1 <= length <= 256:
                    raise ValueError("请求长度不合法")
                request = json.loads(self.rfile.read(length))
                x, y = request["x"], request["y"]
                if type(x) is not int or type(y) is not int:
                    raise ValueError("格坐标必须为整数")
                if type(request["map_id"]) is not int or request["map_id"] != nav_map_payload["map_id"]:
                    raise ValueError("地图版本不匹配")
                n = nav_map_payload["grid_cells"]
                if not (0 <= x < n and 0 <= y < n):
                    raise ValueError("终点越界")
                if nav_map_payload["occupied"][y * n + x]:
                    raise ValueError("终点位于障碍或安全区")
            except (ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
                self.send_json(400, {"error": str(error)})
                return
            with state.condition:
                serial_connected = state.status.get("serial_connected", False)
            if not serial_connected:
                self.send_json(503, {"error": "树莓派 USB 串口未连接"})
                return
            if not state.queue_nav_goal(x, y):
                self.send_json(409, {"error": "上一终点仍在排队，请等待发送结果"})
                return
            self.send_json(202, {"state": "queued", "x": x, "y": y,
                                 "note": "仅已排队；不代表 FPGA 已接收或开始移动"})

        def log_message(self, _format, *_args):
            return

    return DashboardHandler


def draw_detection(frame, detection, selected=False, red_ratio=None):
    x1, y1, x2, y2 = map(
        int,
        [detection.x1, detection.y1, detection.x2, detection.y2],
    )
    color = (60, 220, 120) if selected else (255, 170, 50)
    thickness = 3 if selected else 2
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, thickness)
    text = f"{detection.class_name} {detection.confidence:.2f}"
    if detection.source == 'a4_partial_digit':
        text += ' [PARTIAL PAPER / INTACT DIGIT]'
    if detection.source == 'near_context':
        text += ' close'
    if red_ratio is not None:
        text += f" red {red_ratio:.0%}"
    (tw, th), _ = cv2.getTextSize(
        text, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2
    )
    label_right = min(frame.shape[1] - 1, x1 + tw + 10)
    if y1 >= th + 12:
        label_top = y1 - th - 10
        label_bottom = y1
        text_y = y1 - 5
    else:
        label_top = y1
        label_bottom = min(frame.shape[0] - 1, y1 + th + 10)
        text_y = min(frame.shape[0] - 5, y1 + th + 5)
    cv2.rectangle(
        frame,
        (x1, label_top),
        (label_right, label_bottom),
        color,
        -1,
    )
    cv2.putText(
        frame,
        text,
        (x1 + 5, text_y),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (15, 20, 28),
        2,
    )


def create_aligner(cfg):
    vcfg = cfg.get("visual_alignment", {})
    return VisualAlignmentController(
        center_target=vcfg.get("center_target", 5000),
        center_deadband=vcfg.get("center_deadband", 0.08),
        max_vy=vcfg.get("max_vy", 0.22),
        lateral_gain=vcfg.get("lateral_gain", 1.15),
        smoothing_alpha=vcfg.get("smoothing_alpha", 0.35),
        search_omega=vcfg.get("search_omega", 0.20),
        target_confirm_frames=vcfg.get("target_confirm_frames", 2),
        lost_confirm_frames=vcfg.get("lost_confirm_frames", 2),
    )


def run(config_path, host, port, jpeg_quality):
    cfg = load_config(config_path)
    geometry_reporter = MissionGeometryReporter.from_config(cfg)
    state = DashboardState()
    map_spec = load_map()
    nav_map_payload = {**map_spec, "occupied": occupied_cells(map_spec)}
    # 必须同时配置开关与非空口令；USB 串口在线并不能证明 FPGA 已上电。
    nav_goal_enabled, nav_token, nav_config_error = navigation_settings(cfg)
    state.nav_status["nav_goal_tx_enabled"] = nav_goal_enabled
    if nav_goal_enabled:
        state.nav_status["nav_goal_state"] = "已开放目标下发；请先核对 FPGA 位流与供电"
    elif nav_config_error:
        state.nav_status["nav_goal_state"] = nav_config_error
    state.status.update(state.nav_status)
    html_path = Path(__file__).resolve().parent.parent / "web" / "dashboard.html"
    server = ThreadingHTTPServer(
        (host, port), make_handler(state, html_path, nav_map_payload,
                                  nav_goal_enabled, nav_token)
    )
    server.daemon_threads = True
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    camera = create_camera(cfg["camera"])
    model_cfg = cfg["model"]
    detector = create_detector(cfg)
    names = detector.names
    state.model_classes = names if isinstance(names, dict) else dict(enumerate(names))
    target_cfg = cfg.get("target", {})
    selector = TargetSelector(
        target_cfg.get("class_names", []),
        target_cfg.get("selection", "largest"),
        target_cfg.get("min_area_ratio", 0.0),
        target_cfg.get("red_bottle", {}),
    )
    aligner = create_aligner(cfg)
    aim_y_target = float(cfg.get('visual_alignment', {}).get('aim_y_target', 5000))
    if not math.isfinite(aim_y_target) or not 0 <= aim_y_target <= 10000:
        raise ValueError('aim_y_target must be in [0, 10000]')

    links = TransportHub(cfg)

    hostname = socket.gethostname()
    started = time.monotonic()
    previous = time.perf_counter()
    fps = 0.0
    seq = 0
    frame_id = 0
    last_hb = 0
    hb_interval = cfg.get("serial", {}).get(
        "heartbeat_interval_ms", 500
    )
    # SIN9 accepts only perception on J21/115200. No area-derived F/B bytes.
    motion_protocol = "locked_target_v1"
    motion_enabled = False
    last_motion_command = "S"

    def transmit_queued_nav_goal():
        """Send a complete SIN6/SIN7 path independently of camera frames."""
        nonlocal seq
        if not links.enabled:
            return
        queued_goal = state.take_nav_goal()
        if queued_goal is None:
            return
        x, y = queued_goal
        route = shortest_path_from(
            map_spec, nav_map_payload["occupied"],
            tuple(map_spec["start_cell"]), (x, y)
        )
        if len(route) < 2:
            state.nav_sent(x, y, False)
            return
        try:
            directions = route_direction_codes(route)
            frame = pack_nav_path(seq, x, y, directions)
            sent = links.serial.send(frame)
        except (ValueError, OSError):
            sent = False
            directions = []
        if sent:
            seq = (seq + 1) & 0xFFFF
        state.nav_sent(
            x, y, sent,
            (seq - 1) & 0xFFFF if sent else None,
            len(directions) if sent else None,
        )

    print(f"[GUI] http://{host}:{port}")
    try:
        links.open()
        try:
            camera.open()
        except Exception as error:
            serial_status = links.status()["serial"]
            state.update_status(
                online=False,
                message=f"相机未就绪：{error}",
                serial_enabled=serial_status["enabled"],
                serial_connected=serial_status["connected"],
                serial_port=serial_status["port"],
                serial_active_port=serial_status["active_port"],
                serial_baudrate=serial_status["baudrate"],
                serial_frames_sent=serial_status["frames_sent"],
                serial_bytes_sent=serial_status["bytes_sent"],
                serial_last_msg_type=serial_status["last_msg_type"],
                serial_last_seq=serial_status["last_seq"],
                serial_last_sent_age_ms=serial_status["last_sent_age_ms"],
                serial_last_error=serial_status["last_error"],
            )
            print(f"[GUI] Camera unavailable: {error}")
            while True:
                transmit_queued_nav_goal()
                time.sleep(0.1)
        while True:
            ok, frame = camera.read()
            frame_captured_unix_s = time.time()  # application receipt time, not sensor exposure time
            if not ok:
                state.update_status(online=False, message="相机读取失败")
                time.sleep(0.2)
                continue

            now_ms = int(time.monotonic() * 1000)
            for sensor_line in links.serial.receive_lines():
                mission = parse_mission_status(sensor_line)
                if mission is not None:
                    with state.condition:
                        state.task_status['mission_fpga'] = mission
                        state.task_status['mission_fpga_received_at'] = time.monotonic()
                    continue
                sensor = parse_sensor_line(sensor_line)
                if sensor is None:
                    continue
                state.update_status(
                    fpga_imu_valid=sensor["imu_valid"],
                    fpga_tof_valid=sensor["tof_valid"],
                    fpga_distance_mm=sensor["distance_mm"],
                    fpga_hard_stop=sensor["hard_stop"],
                    fpga_roll_deg=sensor.get("roll_deg"),
                    fpga_pitch_deg=sensor.get("pitch_deg"),
                    fpga_yaw_deg=sensor.get("yaw_deg"),
                    fpga_faults=sensor["faults"],
                    fpga_wheel_fault=sensor["wheel_fault"],
                    fpga_sensor_received_at=time.monotonic(),
                )
            with state.condition:
                requested_category = state.task_status['task_target_class']
            detections = detector.detect(frame, target_class=requested_category)
            target, detection_rows, task, revision = state.process_detections(detections, frame_id, frame)
            observation = TargetObservation.from_detection(now_ms, target)
            if target is None and (task['task_lock_id'] or task['task_mode']=='mission'):
                observation.class_id = task['task_class_id']
                observation.class_name = task['task_target_class']
            alignment = aligner.update(observation)
            geometry = None
            if links.enabled:
                # A newer UI selection wins over an in-flight inference frame.
                with state.condition:
                    if revision != state.task_revision:
                        observation.valid = False
                        task = dict(state.task_status)
                        observation.class_id = task['task_class_id']
                        task['task_target_confirmed'] = False
                    if task['task_mode'] == 'mission' and task.get('mission_id'):
                        if geometry_reporter is not None:
                            geometry = geometry_reporter.observe(target,
                                age_ms=int(time.monotonic()*1000)-now_ms,
                                confirmed=task.get('task_target_confirmed',False) and observation.valid)
                            packet = pack_visual_primary_observation(seq, observation, alignment, frame_id,
                                task['task_lock_id'], task.get('task_target_confirmed',False),
                                task['mission_id'], task['mission_color'], geometry=geometry)
                        else:
                            packet = pack_mission_observation(seq, observation, alignment, frame_id,
                                task['task_lock_id'], task.get('task_target_confirmed',False),
                                task['mission_id'], task['mission_color'])
                    else:
                        packet = pack_locked_target(
                            seq, observation, alignment, frame_id,
                            task['task_lock_id'], task['task_mode'] == 'follow',
                            task.get('task_target_confirmed', False))
                    # Mission readiness must mean the physical USB write succeeded;
                    # a UDP diagnostic receiver cannot stand in for the FPGA.
                    if task['task_mode']=='mission':
                        sent = links.serial.send(packet)
                        links.udp.send(packet)
                    else:
                        sent = links.send(packet)
                    if sent and task['task_mode']=='mission':
                        state.task_status.update(mission_perception_tx_id=task['mission_id'],
                                                 mission_perception_tx_at=time.monotonic())
                    state.task_status['task_actuator'] = (
                        "已写出锁定帧，等待 FPGA 回传确认" if sent
                        else "串口未写出，请检查 USB 连接")
                seq = (seq + 1) & 0xFFFF

            annotated = frame.copy()
            for detection in detections:
                draw_detection(annotated, detection, detection is target,
                               selector.red_ratios.get(id(detection)))

            height, width = annotated.shape[:2]
            cv2.line(
                annotated,
                (min(width-1, round(width * aligner.center_target / 10000)), 0),
                (min(width-1, round(width * aligner.center_target / 10000)), height-1),
                (230, 230, 230),
                1,
            )
            # This is a calibrated aim guide, not an observed ToF hit location.
            cv2.drawMarker(annotated,
                (min(width-1, round(width * aligner.center_target / 10000)),
                 min(height-1, round(height * aim_y_target / 10000))),
                (0, 220, 255), cv2.MARKER_CROSS, 20, 1)
            cv2.putText(
                annotated,
                f"{alignment.state}  FPS {fps:.1f}",
                (16, height - 18),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.65,
                (255, 255, 255),
                2,
            )

            now = time.perf_counter()
            current_fps = 1.0 / max(1e-6, now - previous)
            previous = now
            fps = current_fps if fps == 0.0 else fps * 0.8 + current_fps * 0.2

            success, encoded = cv2.imencode(
                ".jpg",
                annotated,
                [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality],
            )
            if not success:
                continue

            transport_status = links.status()
            serial_status = transport_status["serial"]
            udp_status = transport_status["udp"]
            target_area_ratio = (
                observation.w * observation.h / 100000000.0
                if observation.valid
                else 0.0
            )
            status = {
                **detector.status,
                'visual_tools_revision': 'aim-data-v1-20261030',
                'mission_geometry_enabled': geometry_reporter is not None,
                'mission_geometry_observation': geometry,
                'mission_geometry_scope': 'experimental0x16; calibrated advisory geometry, not measured range',
                'frame_captured_unix_s': frame_captured_unix_s,
                'alignment_center_target': aligner.center_target,
                'alignment_aim_y_target': aim_y_target,
                'alignment_calibration_note': '固定对准参考；竖向仅作标线，不控制车体高度',
                "online": True,
                "message": "视觉服务运行中",
                "hostname": hostname,
                "uptime_s": round(time.monotonic() - started),
                "fps": round(fps, 2),
                "resolution": f"{width}×{height}",
                "model": detector.label,
                "mission_strategy": "a4_digits" if cfg.get("perception",{}).get("backend")=="a4_digits" else "semantic",
                "mission_categories": list(state.model_classes.values()),
                "frame_id": frame_id,
                "alignment_state": alignment.state,
                "center_error": round(alignment.center_error, 3),
                "target_area_ratio": round(target_area_ratio, 4),
                "serial_enabled": serial_status["enabled"],
                "serial_connected": serial_status["connected"],
                "serial_port": serial_status["port"],
                "serial_active_port": serial_status["active_port"],
                "serial_baudrate": serial_status["baudrate"],
                "serial_frames_sent": serial_status["frames_sent"],
                "serial_bytes_sent": serial_status["bytes_sent"],
                "serial_last_msg_type": serial_status["last_msg_type"],
                "serial_last_seq": serial_status["last_seq"],
                "serial_last_sent_age_ms": serial_status["last_sent_age_ms"],
                "serial_last_error": serial_status["last_error"],
                "motion_protocol": motion_protocol,
                "motion_commands_enabled": motion_enabled,
                "motion_last_command": last_motion_command,
                # 这里是本地将要/已经写出的视觉状态，不代表 FPGA 已收到。
                "vision_target_valid": bool(observation.valid),
                "vision_target_confirmed": bool(
                    observation.valid and alignment.state not in ("HOLD", "ERROR")
                ),
                "udp_enabled": udp_status["enabled"],
                "udp_destination": (
                    f"{udp_status['host']}:{udp_status['port']}"
                    if udp_status["enabled"]
                    else "未启用"
                ),
                "target_class": (
                    target.class_name
                    if target is not None else "无"
                ),
                "red_filter_enabled": False,
                "red_min_ratio": 0.0,
                "detection_count": len(detection_rows),
                "detections": detection_rows,
            }
            # Sensor metadata is from asynchronous telemetry, not a measurement
            # synchronized with this image. Preserve its age for later review.
            with state.condition:
                status.update({k: state.status.get(k) for k in (
                    'fpga_distance_mm', 'fpga_tof_valid')})
                sensor_at = state.status.get('fpga_sensor_received_at')
                status['fpga_sensor_age_ms'] = (round((time.monotonic()-sensor_at)*1000)
                                                if sensor_at is not None else None)
            state.update(encoded.tobytes(), status, raw_frame=frame)
            frame_id = (frame_id + 1) & 0xFFFFFFFF
    except KeyboardInterrupt:
        print("\n[GUI] Ctrl+C received")
    except Exception as error:
        state.update_status(online=False, message=f"运行错误：{error}")
        raise
    finally:
        links.close()
        camera.close()
        server.shutdown()
        server.server_close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config/config-pi.yaml")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--jpeg-quality", type=int, default=82)
    args = parser.parse_args()
    run(
        args.config,
        args.host,
        args.port,
        max(40, min(95, args.jpeg_quality)),
    )


if __name__ == "__main__":
    main()
