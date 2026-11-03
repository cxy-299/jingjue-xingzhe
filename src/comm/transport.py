from src.comm.serial_link import SerialLink
from src.comm.udp_link import UdpLink


class TransportHub:
    """Broadcast frames to the real FPGA UART and optional UDP mock."""

    def __init__(self, cfg):
        serial_cfg = cfg.get("serial", {})
        self.serial = SerialLink(
            enabled=serial_cfg.get("enabled", False),
            port=serial_cfg.get("port", "/dev/serial0"),
            baudrate=serial_cfg.get("baudrate", 115200),
            timeout=serial_cfg.get("timeout", 0.0),
            write_timeout=serial_cfg.get("write_timeout", 0.1),
            reconnect_interval_s=serial_cfg.get(
                "reconnect_interval_s", 2.0
            ),
        )

        mock_cfg = cfg.get("mock_fpga", {})
        self.udp = UdpLink(
            enabled=mock_cfg.get("enabled", False),
            host=mock_cfg.get("host", "127.0.0.1"),
            port=mock_cfg.get("port", 9999),
        )

    @property
    def enabled(self):
        return self.serial.enabled or self.udp.enabled

    def open(self):
        self.serial.open()
        self.udp.open()

    def send(self, data):
        serial_ok = self.serial.send(data)
        udp_ok = self.udp.send(data)
        return serial_ok or udp_ok

    def send_motion(self, command):
        """Send one ASCII F/B/L/R/S command on the configured motion UART."""
        if command not in "FBLRS":
            raise ValueError("invalid motion command")
        return self.serial.send(command.encode("ascii"))

    def status(self):
        return {
            "serial": self.serial.status(),
            "udp": self.udp.status(),
        }

    def close(self):
        self.serial.close()
        self.udp.close()
