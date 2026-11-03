class MockToF:
    """Keyboard-adjustable PC ToF simulator.

    This class exists only for Windows/PC integration testing.
    """

    def __init__(self, start_mm=1500, step_mm=100, min_mm=100, max_mm=3000):
        self.distance_mm = int(start_mm)
        self.step_mm = int(step_mm)
        self.min_mm = int(min_mm)
        self.max_mm = int(max_mm)
        self.valid = True

    def closer(self):
        self.distance_mm = max(self.min_mm, self.distance_mm - self.step_mm)

    def farther(self):
        self.distance_mm = min(self.max_mm, self.distance_mm + self.step_mm)

    def reset(self, value_mm=1500):
        self.distance_mm = max(self.min_mm, min(self.max_mm, int(value_mm)))
        self.valid = True

    def toggle_valid(self):
        self.valid = not self.valid
