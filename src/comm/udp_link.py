import socket


class UdpLink:
    """PC-only transport used to simulate the future UART/FPGA link.

    The bytes placed in each UDP datagram are the SAME protocol frame bytes
    that will later be sent over UART. UDP is only a convenient local cable
    replacement for testing two independent Windows processes.
    """

    def __init__(self, enabled=True, host='127.0.0.1', port=9999):
        self.enabled = bool(enabled)
        self.host = str(host)
        self.port = int(port)
        self.sock = None
        self.frames_sent = 0
        self.bytes_sent = 0
        self.last_error = ''

    def open(self):
        if not self.enabled:
            return
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def send(self, data: bytes):
        if self.enabled and self.sock is not None:
            try:
                written = self.sock.sendto(data, (self.host, self.port))
                self.frames_sent += 1
                self.bytes_sent += written
                self.last_error = ''
                return True
            except OSError as error:
                self.last_error = str(error)
        return False

    def status(self):
        return {
            'enabled': self.enabled,
            'connected': self.enabled and self.sock is not None,
            'host': self.host,
            'port': self.port,
            'frames_sent': self.frames_sent,
            'bytes_sent': self.bytes_sent,
            'last_error': self.last_error,
        }

    def close(self):
        if self.sock is not None:
            self.sock.close()
            self.sock = None
