@echo off
call .venv\Scripts\activate
python -m src.main --config config/config.yaml
pause
