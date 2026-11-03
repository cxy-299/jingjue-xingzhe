from abc import ABC, abstractmethod
class CameraBase(ABC):
    @abstractmethod
    def open(self): pass
    @abstractmethod
    def read(self): pass
    @abstractmethod
    def close(self): pass
