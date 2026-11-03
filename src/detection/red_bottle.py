"""在 YOLO 的 bottle 框内估计红色覆盖率；仅作颜色二次筛选。"""

import cv2


def red_coverage(frame_bgr, detection, min_saturation=90, min_value=55):
    """返回框中心区域中红色像素占比，范围 0..1。

    输入必须是 OpenCV BGR 图像。跳过框边缘 10%，减少背景和绘制边框干扰。
    HSV 的红色跨越色相 0 度边界，因此必须合并两段阈值。
    """
    height, width = frame_bgr.shape[:2]
    x1 = max(0, min(width, int(detection.x1)))
    y1 = max(0, min(height, int(detection.y1)))
    x2 = max(0, min(width, int(detection.x2)))
    y2 = max(0, min(height, int(detection.y2)))
    if x2 <= x1 or y2 <= y1:
        return 0.0

    inset_x = int((x2 - x1) * 0.10)
    inset_y = int((y2 - y1) * 0.10)
    roi = frame_bgr[y1 + inset_y:y2 - inset_y,
                    x1 + inset_x:x2 - inset_x]
    if roi.size == 0:
        return 0.0

    hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
    low_red = cv2.inRange(hsv, (0, min_saturation, min_value), (10, 255, 255))
    high_red = cv2.inRange(hsv, (170, min_saturation, min_value), (179, 255, 255))
    red_pixels = cv2.countNonZero(low_red | high_red)
    return red_pixels / (roi.shape[0] * roi.shape[1])
