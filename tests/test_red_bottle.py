import numpy as np

from src.core.messages import Detection
from src.detection.red_bottle import red_coverage
from src.detection.target_selector import TargetSelector


def bottle(x1, x2):
    return Detection(39, "bottle", 0.9, x1, 10, x2, 90, 200, 100)


def test_red_candidate_selected_and_blue_rejected():
    # OpenCV BGR：红色为 (0, 0, 255)，蓝色为 (255, 0, 0)。
    image = np.zeros((100, 200, 3), dtype=np.uint8)
    image[10:90, 10:90] = (0, 0, 255)
    image[10:90, 110:190] = (255, 0, 0)
    red, blue = bottle(10, 90), bottle(110, 190)
    selector = TargetSelector(["bottle"], red_bottle={
        "enabled": True, "min_red_ratio": 0.12,
    })
    assert selector.choose([blue, red], image) is red
    assert selector.red_ratios[id(red)] > 0.9
    assert selector.red_ratios[id(blue)] == 0.0


def test_red_filter_never_accepts_unchecked_bottle():
    selector = TargetSelector(["bottle"], red_bottle={"enabled": True})
    assert selector.choose([bottle(10, 90)]) is None


def test_invalid_box_and_image_boundary_are_safe():
    image = np.zeros((20, 20, 3), dtype=np.uint8)
    assert red_coverage(image, Detection(39, "bottle", .9, 10, 10, 5, 5,
                                         20, 20)) == 0.0
    image[:, :] = (0, 0, 255)
    assert red_coverage(image, Detection(39, "bottle", .9, -10, -10, 30, 30,
                                         20, 20)) > 0.9
