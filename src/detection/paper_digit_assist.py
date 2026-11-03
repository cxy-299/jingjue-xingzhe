"""Bounded, current-frame paper geometry; never an identity or range source."""
import cv2
import numpy as np
from src.detection.a4_digit import A4DigitDetector


def paper_views(frame):
    """At most two observed portrait quadrilaterals, rectified to 210x297.

    All four sides need measured edge support. A rectangle is only a region
    to inspect: classification still requires a complete, isolated digit.
    Missing paper edges simply leave the independent near-digit path in use.
    """
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    height, width = gray.shape
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 35, 110)
    support = cv2.dilate(edges, np.ones((5, 5), np.uint8))
    bright = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]
    candidates = []
    for mask in (edges, bright):
        contours, _ = cv2.findContours(mask, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:32]:
            area = cv2.contourArea(contour)
            if not .045 * width * height < area < .88 * width * height:
                continue
            polygon = cv2.approxPolyDP(contour, .025 * cv2.arcLength(contour, True), True)
            if len(polygon) == 4 and cv2.isContourConvex(polygon):
                candidates.append(polygon)
    # Do not run the old combinatorial marker/line reconstruction here.
    # Basket grids can produce hundreds of unrelated mark/line pairings.
    # Missing edges fall back to the independent intact-glyph reader.
    accepted = []
    destination = np.float32([[0, 0], [209, 0], [209, 296], [0, 296]])
    for candidate in candidates:
        quad = A4DigitDetector.ordered_quad(candidate)
        if (np.any(quad[:, 0] < 2) or np.any(quad[:, 0] >= width - 2) or
                np.any(quad[:, 1] < 2) or np.any(quad[:, 1] >= height - 2)):
            continue
        lengths = np.linalg.norm(quad - np.roll(quad, -1, axis=0), axis=1)
        ratio = (lengths[1] + lengths[3]) / max(1, lengths[0] + lengths[2])
        if not 1.10 < ratio < 1.95 or min(lengths) < 65:
            continue
        if max(lengths[0], lengths[2]) / min(lengths[0], lengths[2]) > 1.65:
            continue
        if any(np.mean(support[
                np.rint((a + (b - a) * np.linspace(.08, .92, 50)[:, None])[:, 1]).astype(int),
                np.rint((a + (b - a) * np.linspace(.08, .92, 50)[:, None])[:, 0]).astype(int)] > 0) < .62
               for a, b in zip(quad, np.roll(quad, -1, axis=0))):
            continue
        if any(cv2.intersectConvexConvex(quad, old[0])[0] /
               max(1, min(cv2.contourArea(quad), cv2.contourArea(old[0]))) > .75
               for old in accepted):
            continue
        transform = cv2.getPerspectiveTransform(quad, destination)
        page = cv2.warpPerspective(frame, transform, (210, 297))
        # A mostly light sheet with a darker, contrasting glyph. This rejects
        # dark furniture rectangles; it does not establish physical A4 size.
        pg = cv2.cvtColor(page, cv2.COLOR_BGR2GRAY)
        if np.median(pg) < 65 or np.percentile(pg, 85) - np.percentile(pg, 5) < 30:
            continue
        accepted.append((quad, page, np.linalg.inv(transform)))
        if len(accepted) == 2:
            break
    return accepted


def illumination_view(page):
    """Remove smooth illumination gradients, without filling missing strokes."""
    gray = cv2.cvtColor(page, cv2.COLOR_BGR2GRAY)
    background = cv2.GaussianBlur(gray, (0, 0), 21)
    flat = cv2.divide(gray, np.maximum(background, 1), scale=210)
    return cv2.cvtColor(flat, cv2.COLOR_GRAY2BGR)
