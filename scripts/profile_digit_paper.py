"""Read-only candidate profiling on a saved live background frame."""
import cProfile
import importlib.util
from pathlib import Path
import pstats
import sys
import time
import cv2
ROOT=Path('/home/pi/ling_shu_vision');STAGE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import src.detection
src.detection.__path__.insert(0,str(STAGE/'src/detection'))
from src.detection.printed_digit import PrintedDigitDetector

frame=cv2.imread(str(STAGE/'evidence/empty_scene.jpg'));assert frame is not None
for enabled in (False,True):
    detector=PrintedDigitDetector({'_paper_enabled':enabled})
    profiler=cProfile.Profile();profiler.enable();detector.detect(frame);profiler.disable()
    print('PAPER',enabled,detector.status)
    pstats.Stats(profiler).sort_stats('cumulative').print_stats(18)
