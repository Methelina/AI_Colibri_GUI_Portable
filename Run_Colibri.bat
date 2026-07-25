@echo off
setlocal
cd /d "%~dp0"

set "PYTHON_EXE=%~dp0colibri_env\Scripts\python.exe"
if not exist "%PYTHON_EXE%" (
    echo ERROR: colibri_env not found. Run Install_Colibri.bat first.
    pause
    exit /b 1
)

if defined COLI_MODEL goto :launch
if defined SNAP set "COLI_MODEL=%SNAP%" & goto :launch
echo Model not set. Use GUI to configure or download.

:launch
"%PYTHON_EXE%" "%~dp0scripts\colibri_gui.py"
exit /b %ERRORLEVEL%
