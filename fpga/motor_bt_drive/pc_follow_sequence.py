"""Cancel stale follow reversals before they can issue a new direction."""
import serial


class FollowCommandSequencer:
    def __init__(self, after, after_cancel, get_gate, neutral_ms=140, on_error=None):
        self.after, self.after_cancel, self.get_gate = after, after_cancel, get_gate
        self.neutral_ms = neutral_ms
        self.on_error = on_error
        self.timer = None
        self.pending = None
        self.generation = 0

    def cancel(self):
        self.generation += 1
        if self.timer is not None:
            self.after_cancel(self.timer)
        self.timer = self.pending = None

    def send(self, direction):
        gate = self.get_gate()
        if gate is None:
            self.cancel()
            return
        if direction == 'S':
            self.cancel()
            gate.stop()
            return
        if self.pending == direction:
            return
        self.cancel()
        if gate.held == direction:
            gate.refresh()
        elif gate.held is not None:
            gate.stop()
            self.pending = direction
            token = self.generation

            def resume():
                if token != self.generation or self.pending != direction:
                    return
                self.timer = self.pending = None
                try:
                    self.send(direction)
                except (serial.SerialException, OSError) as error:
                    self.cancel()
                    if self.on_error is None:
                        raise
                    self.on_error(error)
            self.timer = self.after(self.neutral_ms, resume)
        else:
            gate.press(direction)
