import time


class SerialLink:
    """Fail-safe UART sender with automatic reconnect.

    A missing/disconnected FPGA must not stop camera inference or the web GUI.
    The link records the error and retries in the background on later sends.
    """

    def __init__(
        self,
        enabled=False,
        port="/dev/serial0",
        baudrate=115200,
        timeout=0.0,
        write_timeout=0.1,
        reconnect_interval_s=2.0,
        serial_factory=None,
        port_lister=None,
    ):
        self.enabled = bool(enabled)
        self.port = str(port)
        self.baudrate = int(baudrate)
        self.timeout = float(timeout)
        self.write_timeout = float(write_timeout)
        self.reconnect_interval_s = max(0.1, float(reconnect_interval_s))
        self._serial_factory = serial_factory
        self._port_lister = port_lister
        self.ser = None
        self.active_port = ""
        self.frames_sent = 0
        self.bytes_sent = 0
        self.last_msg_type = None
        self.last_seq = None
        self.last_sent_monotonic = None
        self.last_error = ""
        self._next_reconnect = 0.0
        self._rx_buffer = bytearray()
        self.rx_lines = 0

    @property
    def connected(self):
        return self.ser is not None and bool(
            getattr(self.ser, "is_open", True)
        )

    def _close_port(self):
        if self.ser is not None:
            try:
                self.ser.close()
            except Exception:
                pass
            self.ser = None
        self.active_port = ""
        self._rx_buffer.clear()

    def _resolve_port(self):
        # USB 串口可能由 ttyUSB0 变为 ttyUSB1；自动模式只接受唯一的 CH340。
        # 多个候选时宁可等待人工指定，也不能把视觉帧发到错误设备。
        if self.port != "auto_usb_ch340":
            return self.port
        if self._port_lister is None:
            from serial.tools import list_ports
            ports = list_ports.comports()
        else:
            ports = self._port_lister()
        matches = [
            item.device for item in ports
            if getattr(item, "vid", None) == 0x1A86
            and (
                getattr(item, "pid", None) in (0x7523, 0x55D4)
                or "CH340" in str(getattr(item, "description", "")).upper()
            )
        ]
        if len(matches) != 1:
            raise OSError(
                f"Expected one CH340 USB UART, found {len(matches)}; "
                "set serial.port to the exact /dev/serial/by-id path if needed"
            )
        return matches[0]

    def _connect(self, force=False):
        if not self.enabled:
            return False
        if self.connected:
            return True

        now = time.monotonic()
        if not force and now < self._next_reconnect:
            return False
        self._next_reconnect = now + self.reconnect_interval_s

        try:
            active_port = self._resolve_port()
            if self._serial_factory is None:
                import serial

                factory = serial.Serial
            else:
                factory = self._serial_factory
            self.ser = factory(
                active_port,
                self.baudrate,
                timeout=self.timeout,
                write_timeout=self.write_timeout,
            )
            self.active_port = active_port
            self.last_error = ""
            return True
        except Exception as error:
            self.ser = None
            self.last_error = str(error)
            return False

    def open(self):
        return self._connect(force=True)

    def send(self, data: bytes):
        if not self.enabled or not self._connect():
            return False

        try:
            written = self.ser.write(data)
            if written != len(data):
                raise IOError(
                    f"UART short write: {written}/{len(data)} bytes"
                )
            self.frames_sent += 1
            self.bytes_sent += written
            self.last_sent_monotonic = time.monotonic()
            if len(data) >= 10 and data[:2] == b"\xAA\x55":
                self.last_msg_type = data[3]
                self.last_seq = data[4] | (data[5] << 8)
            self.last_error = ""
            return True
        except Exception as error:
            self.last_error = str(error)
            self._close_port()
            self._next_reconnect = time.monotonic() + self.reconnect_interval_s
            return False


    def receive_lines(self, limit=64):
        """Read newline-delimited FPGA diagnostic frames without blocking."""
        if not self.connected:
            return []
        try:
            waiting = int(getattr(self.ser, "in_waiting", 0))
            if waiting <= 0:
                return []
            self._rx_buffer.extend(self.ser.read(min(waiting, 8192)))
            lines = []
            while b"\n" in self._rx_buffer and len(lines) < limit:
                raw, _, rest = self._rx_buffer.partition(b"\n")
                self._rx_buffer = bytearray(rest)
                line = raw.decode("ascii", "replace").strip()
                if line:
                    lines.append(line)
                    self.rx_lines += 1
            return lines
        except Exception as error:
            self.last_error = str(error)
            self._close_port()
            return []

    def status(self):
        return {
            "enabled": self.enabled,
            "connected": self.connected,
            "port": self.port,
            "active_port": self.active_port,
            "baudrate": self.baudrate,
            "frames_sent": self.frames_sent,
            "bytes_sent": self.bytes_sent,
            "last_msg_type": self.last_msg_type,
            "last_seq": self.last_seq,
            "last_sent_age_ms": (
                None if self.last_sent_monotonic is None else
                round((time.monotonic() - self.last_sent_monotonic) * 1000)
            ),
            "last_error": self.last_error,
            "rx_lines": self.rx_lines,
        }

    def close(self):
        self._close_port()
