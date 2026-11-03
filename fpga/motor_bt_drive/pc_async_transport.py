"""Full-duplex serial workers; Tk never waits on a Bluetooth driver call.

write() acknowledges queue admission, not FPGA receipt. TX counters/events are
published only after a full OS write. A queued S discards pending motion frames.
"""
from collections import deque
from datetime import datetime
import queue
import threading
import time

import serial


class AsyncTrackedPort:
    def __init__(self, port, event_callback=None):
        self.port = port
        self.tx_bytes = 0
        self.last_tx = '无'
        self._callback = event_callback
        self._closed = threading.Event()
        self._stop_written = threading.Event()
        self._condition = threading.Condition()
        self._pending = deque()
        self._lines = queue.Queue(maxsize=2048)
        self._events = queue.Queue(maxsize=2048)
        self._error = None
        self._rx_thread = threading.Thread(target=self._receive, daemon=True)
        self._tx_thread = threading.Thread(target=self._transmit, daemon=True)
        self._rx_thread.start()
        self._tx_thread.start()

    def _fail(self, error):
        with self._condition:
            if self._error is None:
                self._error = f'{type(error).__name__}: {error}'
            self._pending.clear()
            self._condition.notify_all()

    def _check(self):
        if self._error is not None:
            raise serial.SerialException(str(self._error))
        if self._closed.is_set():
            raise serial.SerialException('串口已关闭')

    def write(self, data):
        data = bytes(data)
        with self._condition:
            self._check()
            if data.lower() == b's':
                self._pending.clear()
                self._stop_written.clear()
            elif len(self._pending) >= 64:
                self._fail('蓝牙发送队列拥塞，已取消待发运动')
                self._check()
            self._pending.append(data)
            self._condition.notify()
        return len(data)

    def _transmit(self):
        try:
            while not self._closed.is_set():
                with self._condition:
                    while not self._pending and not self._closed.is_set() and self._error is None:
                        self._condition.wait(.05)
                    if self._closed.is_set() or self._error is not None:
                        return
                    data = self._pending.popleft()
                start = time.monotonic()
                count = self.port.write(data)
                elapsed = time.monotonic() - start
                if count != len(data):
                    raise serial.SerialTimeoutException(f'仅写入 {count}/{len(data)} 字节')
                self.tx_bytes += count
                self.last_tx = datetime.now().strftime('%H:%M:%S')
                if data.lower() == b's':
                    self._stop_written.set()
                self._events.put_nowait('TX完成: ' +
                    (data.hex(' ') if data.startswith(b'\xaa\x55') else repr(data)) +
                    f' · 驱动写入{elapsed*1000:.1f}ms')
                if elapsed > .25:
                    raise serial.SerialTimeoutException(f'蓝牙驱动单次写入{elapsed*1000:.1f}ms，超过250ms；队列已取消，需人工重连')
        except Exception as error:
            if not self._closed.is_set():
                self._fail(error)

    def _receive(self):
        buffer = b''
        try:
            while not self._closed.is_set() and self._error is None:
                start = time.monotonic()
                data = self.port.read(512)
                elapsed = time.monotonic() - start
                if elapsed > .2:
                    self._events.put_nowait(f'RX驱动调用耗时{elapsed*1000:.1f}ms；GUI未参与该调用')
                if data:
                    buffer += data
                    if len(buffer) > 8192:
                        raise serial.SerialException('接收帧超过8192字节或缺少换行')
                    while b'\n' in buffer:
                        line, buffer = buffer.split(b'\n', 1)
                        line = line.rstrip(b'\r')
                        if line:
                            self._lines.put_nowait(line.decode('ascii', 'replace'))
                else:
                    self._closed.wait(.005)
        except Exception as error:
            if not self._closed.is_set():
                self._fail(error)

    def poll_lines(self):
        self._check()
        for _ in range(100):
            try: event = self._events.get_nowait()
            except queue.Empty: break
            if self._callback is not None:
                self._callback(event)
        result = []
        for _ in range(100):
            try: result.append(self._lines.get_nowait())
            except queue.Empty: break
        return result

    def close(self):
        if self._closed.is_set():
            return
        # Bounded best effort: allow the priority S to reach the OS before
        # discarding the queue. This is still not an FPGA acknowledgement.
        if self._error is None:
            try:
                self.write(b'S')
                self._stop_written.wait(.05)
            except serial.SerialException:
                pass
        self._closed.set()
        with self._condition:
            self._pending.clear()
            self._condition.notify_all()
        self.port.close()
