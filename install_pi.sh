#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "[1/5] apt update"
sudo apt update

echo "[2/5] install Raspberry Pi camera/OpenCV/Python packages"
sudo apt install -y \
  python3-picamera2 \
  python3-opencv \
  python3-torch \
  python3-torchvision \
  python3-matplotlib \
  python3-psutil \
  python3-scipy \
  python3-yaml \
  python3-serial \
  python3-tqdm \
  python3-pandas \
  python3-seaborn \
  python3-cpuinfo \
  python3-venv \
  python3-pip

echo "[3/5] create virtual environment with system packages"
if [ ! -d ".venv" ]; then
  python3 -m venv .venv --system-site-packages
fi

echo "[4/5] install Python packages"
# Raspberry Pi OS Bookworm 提供的 pip 已足够；升级到新版可能导致
# 通过临时 SOCKS 代理安装时触发 urllib3 PoolKey 参数兼容性错误。
# ARM64 上让 apt 提供 CPU 版 PyTorch；不要让 pip 自动解析 torch，
# 否则新版本可能下载仅适用于 NVIDIA GPU 的 CUDA 依赖。
./.venv/bin/python -m pip install --no-deps -r requirements-pi.txt

echo "[5/5] verify imports"
./.venv/bin/python - <<'PY'
import cv2
import torch
import yaml
from picamera2 import Picamera2
from ultralytics import YOLO
print("Pi Python environment OK")
print("OpenCV:", cv2.__version__)
print("PyTorch:", torch.__version__)
PY

echo
echo "Installation complete."
echo "Next:"
echo "  rpicam-hello -t 5000"
echo "  ./.venv/bin/python -m scripts.pi_camera_smoke_test --config config/config-pi.yaml"
