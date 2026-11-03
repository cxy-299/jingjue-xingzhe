"""Background components must not veto an otherwise readable single digit."""
from pathlib import Path

import cv2
import numpy as np
import pytest
from PIL import Image, ImageDraw, ImageFont

from src.core.a4_targets import CLASS_BASE
from src.detection.printed_digit import PrintedDigitDetector

def glyph(text="0", xy=(320, 300), size=160):
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    if not font_path.exists():
        font_path = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    image = Image.new("RGB", (640, 480), (235, 235, 235))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(font_path), size)
    box = draw.textbbox((0, 0), text, font=font)
    draw.text((xy[0] - (box[2] - box[0]) / 2 - box[0],
               xy[1] - (box[3] - box[1]) / 2 - box[1]), text, font=font, fill="black")
    return cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)


@pytest.mark.parametrize("digit", range(10))
def test_edge_background_is_not_a_second_character(digit):
    frame = glyph(str(digit), xy=(245, 260))
    ys, xs = np.where(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) < 100)
    height = int(ys.max() - ys.min() + 1)
    # Under the old height/gap heuristic, this frame-touching solid box
    # counted as another character even though it could not be a glyph.
    top = max(0, int(ys.min()) - height // 2)
    cv2.rectangle(frame, (0, top),
                  (int(xs.min()) - 25, top + 2 * height - 2), (30, 30, 30), -1)
    out = PrintedDigitDetector().detect(frame)
    assert len(out) == 1 and out[0].class_id == CLASS_BASE + digit


def test_reported_zero_with_box_background_20261101():
    path = Path(__file__).parent / "fixtures/a4_whitewall_20261031/raw_zero_background_20261101.jpg"
    frame = cv2.imread(str(path))
    assert frame is not None
    out = PrintedDigitDetector().detect(frame)
    assert len(out) == 1 and out[0].class_id == CLASS_BASE


@pytest.mark.parametrize("text", ["12", "34", "01", "10", "11", "00"])
def test_real_adjacent_digits_remain_rejected(text):
    assert not PrintedDigitDetector().detect(glyph(text))


@pytest.mark.parametrize("side", ["left", "right"])
def test_visible_clipped_neighbour_is_not_treated_as_single_digit(side):
    frame = glyph("00")
    ys, xs = np.where(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) < 100)
    # One complete zero plus a visibly cut second zero is still not a
    # standalone single-digit card. Background rejection must not erase it.
    frame = frame[:, xs.min() + 20:] if side == "left" else frame[:, :xs.max() - 19]
    assert not PrintedDigitDetector().detect(frame)


@pytest.mark.parametrize("edge", ["top", "bottom", "left", "right"])
def test_ink_clipped_at_any_frame_edge_is_still_rejected(edge):
    frame = glyph("0")
    ys, xs = np.where(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) < 100)
    cuts = {"top": frame[ys.min() + 5:, :], "bottom": frame[:ys.max() - 4, :],
            "left": frame[:, xs.min() + 5:], "right": frame[:, :xs.max() - 4]}
    assert not PrintedDigitDetector().detect(cuts[edge])


def test_solid_background_alone_never_creates_a_digit():
    frame = np.full((480, 640, 3), 235, np.uint8)
    cv2.rectangle(frame, (0, 0), (86, 353), (30, 30, 30), -1)
    cv2.rectangle(frame, (380, 0), (639, 384), (30, 30, 30), -1)
    assert not PrintedDigitDetector().detect(frame)
