from src.comm.protocol import HEADER, parse_frame


class FrameStreamParser:
    """Recover complete protocol frames from an arbitrary UART byte stream."""

    def __init__(self, max_payload=256):
        self.max_payload = int(max_payload)
        self.buffer = bytearray()
        self.bad_frames = 0

    def feed(self, data):
        self.buffer.extend(data)
        frames = []

        while True:
            header_index = self.buffer.find(HEADER)
            if header_index < 0:
                self.buffer[:] = self.buffer[-1:] if self.buffer[-1:] == b'\xAA' else b''
                break
            if header_index:
                del self.buffer[:header_index]
            if len(self.buffer) < 8:
                break

            payload_length = int.from_bytes(self.buffer[6:8], 'little')
            if payload_length > self.max_payload:
                del self.buffer[0]
                self.bad_frames += 1
                continue

            frame_length = 10 + payload_length
            if len(self.buffer) < frame_length:
                break

            raw = bytes(self.buffer[:frame_length])
            try:
                frames.append(parse_frame(raw))
                del self.buffer[:frame_length]
            except ValueError:
                del self.buffer[0]
                self.bad_frames += 1

        return frames
