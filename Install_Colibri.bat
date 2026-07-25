@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo  colibri Portable Installer
echo ============================================================

set "CACHE_DIR=%~dp0.cache"
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%" >nul 2>&1
if not exist "%CACHE_DIR%\uv" mkdir "%CACHE_DIR%\uv" >nul 2>&1
if not exist "%CACHE_DIR%\tmp" mkdir "%CACHE_DIR%\tmp" >nul 2>&1
set "UV_CACHE_DIR=%CACHE_DIR%\uv"
set "TMP=%CACHE_DIR%\tmp"
set "TEMP=%CACHE_DIR%\tmp"

set "ENV_DIR=%~dp0colibri_env"
set "PYTHON_EXE=%ENV_DIR%\Scripts\python.exe"
set "UV_EXE=%~dp0bin\uv.exe"
set "UV_VERSION=0.11.6"

if exist "%PYTHON_EXE%" (
    echo Environment already installed.
    set /p "REINSTALL=Reinstall? [Y/N] "
    if /i not "!REINSTALL!"=="Y" goto :done
    if exist "%ENV_DIR%" rmdir /s /q "%ENV_DIR%" >nul 2>&1
)

if not exist "%UV_EXE%" call :download_uv
if not exist "%UV_EXE%" (
    echo ERROR: uv download failed.
    pause
    exit /b 1
)

echo Creating virtual environment (Python 3.12)...
"%UV_EXE%" venv "%ENV_DIR%" --python 3.12
if errorlevel 1 (
    echo ERROR: Failed to create environment.
    pause
    exit /b 1
)

echo Installing dearpygui...
"%UV_EXE%" pip install --python "%PYTHON_EXE%" dearpygui
if errorlevel 1 (
    echo ERROR: dearpygui failed.
    pause
    exit /b 1
)

echo Installing psutil pycurl...
"%UV_EXE%" pip install --python "%PYTHON_EXE%" psutil 2>nul
"%UV_EXE%" pip install --python "%PYTHON_EXE%" pycurl certifi 2>nul

call :download_engine

set "SRC_DIR=%~dp0src\colibri"
if not exist "%SRC_DIR%\.git" (
    where git >nul 2>&1
    if not errorlevel 1 (
        echo Cloning colibri source from GitHub...
        if exist "%SRC_DIR%" rmdir /s /q "%SRC_DIR%" >nul 2>&1
        git clone --depth 1 https://github.com/JustVugg/colibri.git "%SRC_DIR%" >nul 2>&1
        if not errorlevel 1 (
            echo Source cloned.
        ) else (
            echo Git clone failed. Web UI will be unavailable.
        )
    ) else (
        echo Git not found. Source skipped.
    )
)

set "WEB_DIR=%~dp0src\colibri\web"
if not exist "%WEB_DIR%\package.json" goto :skip_web
where node >nul 2>&1
if errorlevel 1 (
    echo Node.js not found. Web UI skipped.
    goto :skip_web
)
if exist "%WEB_DIR%\node_modules" goto :skip_web
echo Installing Web UI dependencies...
pushd "%WEB_DIR%"
call npm install --legacy-peer-deps >nul 2>&1
popd
echo Web UI ready.

:skip_web
echo.
echo Installation complete. Run: Run_Colibri.bat
if not exist "%~dp0coli_cuda.dll" (
    echo GPU: CPU-only. Run build_cuda.cmd for CUDA.
)
echo.

:done
pause
exit /b 0

:download_uv
echo Downloading uv %UV_VERSION%...
set "UV_URL=https://releases.astral.sh/github/uv/releases/download/%UV_VERSION%/uv-x86_64-pc-windows-msvc.zip"
set "UV_ZIP=%~dp0uv.zip"
curl.exe -L -o "%UV_ZIP%" "%UV_URL%" --retry 3 --connect-timeout 30 2>nul
if errorlevel 1 (
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%UV_URL%' -OutFile '%UV_ZIP%'" 2>nul
)
if errorlevel 1 (
    echo ERROR: Cannot download uv. Check internet.
    exit /b 1
)
if not exist "%~dp0bin" mkdir "%~dp0bin" >nul 2>&1
powershell -NoProfile -Command "Expand-Archive -Path '%UV_ZIP%' -DestinationPath '%TMP%\uvx' -Force" 2>nul
for /r "%TMP%\uvx" %%F in (uv.exe) do copy /y "%%F" "%UV_EXE%" >nul 2>&1
for /r "%TMP%\uvx" %%F in (uvx.exe) do copy /y "%%F" "%~dp0bin\uvx.exe" >nul 2>&1
if exist "%TMP%\uvx" rmdir /s /q "%TMP%\uvx" >nul 2>&1
del "%UV_ZIP%" >nul 2>&1
exit /b 0

:download_engine
set "ENGINE_VER=1.1.1"
set "ENGINE_URL=https://github.com/JustVugg/colibri/releases/download/v%ENGINE_VER%/colibri-v%ENGINE_VER%-windows-x86_64.zip"
set "ENGINE_ZIP=%~dp0colibri-release.zip"
if exist "%~dp0colibri.exe" if exist "%~dp0coli" if exist "%~dp0openai_server.py" exit /b 0
echo Downloading colibri engine v%ENGINE_VER%...
curl.exe -L -o "%ENGINE_ZIP%" "%ENGINE_URL%" --retry 3 --connect-timeout 30 2>nul
if errorlevel 1 exit /b 0
powershell -NoProfile -Command "Expand-Archive -Path '%ENGINE_ZIP%' -DestinationPath '%TMP%\eng' -Force" 2>nul
if exist "%TMP%\eng" xcopy /e /y "%TMP%\eng\*" "%~dp0" >nul 2>&1
if exist "%TMP%\eng" rmdir /s /q "%TMP%\eng" >nul 2>&1
del "%ENGINE_ZIP%" >nul 2>&1
exit /b 0
