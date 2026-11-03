@echo off
setlocal
pushd "%~dp0.."
if errorlevel 1 (
    echo Cannot open the project directory.
    pause
    exit /b 1
)
set "SIN12_CONSOLE_PY=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if exist "%SIN12_CONSOLE_PY%" (
    "%SIN12_CONSOLE_PY%" "fpga\motor_bt_drive\pc_unified_console.py" --firmware SIN12 --port COM9 %*
) else (
    py -3 "fpga\motor_bt_drive\pc_unified_console.py" --firmware SIN12 --port COM9 %*
)
set "SIN12_CONSOLE_EXIT=%errorlevel%"
popd
if not "%SIN12_CONSOLE_EXIT%"=="0" (
    echo SIN12 console failed with exit code %SIN12_CONSOLE_EXIT%.
    echo Keep this error text for troubleshooting.
    pause
)
exit /b %SIN12_CONSOLE_EXIT%
