@echo off
cd /d "%~dp0.."
py -3.10 -m scripts.bottle_dataset_gui --port 8092
pause
