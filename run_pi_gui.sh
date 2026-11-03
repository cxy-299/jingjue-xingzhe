#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./.venv/bin/python -m src.web_gui \
  --config config/config-pi.yaml \
  --host 0.0.0.0 \
  --port 8080
