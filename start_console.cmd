@echo off
setlocal
pushd "%~dp0"
if exist ".venv\Scripts\python.exe" (
  ".venv\Scripts\python.exe" "fpga\motor_bt_drive\pc_unified_console.py" --firmware SIN12 --port COM9 %*
) else (
  py -3 "fpga\motor_bt_drive\pc_unified_console.py" --firmware SIN12 --port COM9 %*
)
set "RESULT=%errorlevel%"
popd
exit /b %RESULT%
