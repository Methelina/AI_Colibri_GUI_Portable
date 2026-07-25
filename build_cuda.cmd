@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo  colibri CUDA Build
echo ============================================================
echo.
echo  Prerequisites:
echo    - CUDA Toolkit (nvcc)
echo    - MinGW-w64 (gcc)
echo    - MSVC Build Tools (cl.exe + vcvars64.bat)
echo.

set "CUDA_HOME="
set "GCC="
set "VCVARS="

if defined CUDA_PATH if exist "%CUDA_PATH%\bin\nvcc.exe" set "CUDA_HOME=%CUDA_PATH%"

if not defined CUDA_HOME (
    for /f "delims=" %%I in ('where nvcc.exe 2^>nul') do (
        set "NVCC_PATH=%%I"
        for %%J in ("!NVCC_PATH!\..\..") do set "CUDA_HOME=%%~fJ"
        goto :cuda_found
    )
)

if not defined CUDA_HOME (
    set "BASE=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    set "COUNT=0"
    for /d %%D in ("%BASE%\v*") do (
        if exist "%%D\bin\nvcc.exe" (
            set /a COUNT+=1
            set "CUDA_!COUNT!=%%D"
        )
    )
    if !COUNT! gtr 1 (
        echo Multiple CUDA versions found:
        for /l %%I in (1,1,!COUNT!) do echo   [%%I] !CUDA_%%I!
        set /p "CHOICE=Pick number: "
        call set "CUDA_HOME=%%CUDA_!CHOICE!%%"
    ) else if !COUNT! equ 1 (
        set "CUDA_HOME=!CUDA_1!"
    )
)

if not defined CUDA_HOME (
    echo CUDA not found.
    set /p "CUDA_HOME=Enter CUDA path (e.g. C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6): "
)
if not defined CUDA_HOME exit /b 1
if not exist "%CUDA_HOME%\bin\nvcc.exe" (
    echo ERROR: nvcc.exe not found in %CUDA_HOME%\bin
    exit /b 1
)
set "NVCC=%CUDA_HOME%\bin\nvcc.exe"
echo CUDA: %CUDA_HOME%

where gcc.exe >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%I in ('where gcc.exe 2^>nul') do set "GCC=%%I"
)
if not defined GCC (
    set "COUNT=0"
    for %%D in (
        "C:\msys64\ucrt64\bin\gcc.exe"
        "C:\msys64\mingw64\bin\gcc.exe"
        "C:\mingw64\bin\gcc.exe"
        "C:\MinGW\bin\gcc.exe"
    ) do (
        if exist %%D (
            set /a COUNT+=1
            set "GCC_!COUNT!=%%~D"
        )
    )
    if !COUNT! gtr 1 (
        echo Multiple gcc found:
        for /l %%I in (1,1,!COUNT!) do echo   [%%I] !GCC_%%I!
        set /p "CHOICE=Pick number: "
        call set "GCC=%%GCC_!CHOICE!%%"
    ) else if !COUNT! equ 1 (
        set "GCC=!GCC_1!"
    )
)
if not defined GCC (
    set /p "GCC=Enter full path to gcc.exe: "
)
if not defined GCC exit /b 1
if not exist "%GCC%" (
    echo ERROR: gcc.exe not found at %GCC%
    exit /b 1
)
echo gcc: %GCC%

set "COUNT=0"
for %%D in (
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    "C:\PROGRA~2\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
) do (
    if exist %%D (
        set /a COUNT+=1
        set "V_!COUNT!=%%~D"
    )
)
if !COUNT! gtr 1 (
    echo Multiple MSVC found:
    for /l %%I in (1,1,!COUNT!) do echo   [%%I] !V_%%I!
    set /p "CHOICE=Pick number: "
    call set "VCVARS=%%V_!CHOICE!%%"
) else if !COUNT! equ 1 (
    set "VCVARS=!V_1!"
)
if not defined VCVARS (
    set /p "VCVARS=Enter path to vcvars64.bat: "
)
if not defined VCVARS exit /b 1
if not exist "%VCVARS%" (
    echo ERROR: vcvars64.bat not found at %VCVARS%
    exit /b 1
)
echo MSVC: %VCVARS%

set "CUDA_ARCH=native"
for /f "tokens=*" %%I in ('nvidia-smi --query-gpu=name --format=csv,noheader 2^>nul') do (
    set "GPU=%%I"
    echo !GPU! | findstr /i "RTX.50 Blackwell" >nul && set "CUDA_ARCH=sm_120"
    echo !GPU! | findstr /i "RTX.40 Ada" >nul && set "CUDA_ARCH=sm_89"
    echo !GPU! | findstr /i "RTX.30 Ampere" >nul && set "CUDA_ARCH=sm_86"
    echo !GPU! | findstr /i "RTX.20 Turing" >nul && set "CUDA_ARCH=sm_75"
    echo !GPU! | findstr /i "GTX.10 Pascal" >nul && set "CUDA_ARCH=sm_61"
    goto :arch_done
)
:arch_done
echo GPU arch: %CUDA_ARCH%

set "SRC_DIR=%~dp0src\colibri\c"
if not exist "%SRC_DIR%" (
    echo ERROR: Source directory not found: %SRC_DIR%
    echo Download source from: https://github.com/JustVugg/colibri
    exit /b 1
)

echo.
echo ============================================================
echo  Building...
echo ============================================================

pushd "%SRC_DIR%"

echo [1/3] Building coli_cuda.dll...
set "TMP_BAT=%~dp0_build_cuda_tmp.bat"
(
    echo @echo off
    echo call "%VCVARS%" ^>nul 2^>^&1
    echo if errorlevel 1 echo VCVARS_FAILED ^& exit /b 1
    echo set PATH=%CUDA_HOME%\bin;%%PATH%%
    echo "%NVCC%" -O3 -std=c++17 -arch=%CUDA_ARCH% -Xcompiler=-W3 -shared -DCOLI_CUDA_BUILDING_DLL -L"%CUDA_HOME%\lib\x64" -lcudart backend_cuda.cu -o coli_cuda.dll
    echo if errorlevel 1 echo NVCC_FAILED ^& exit /b 1
) > "%TMP_BAT%"
call "%TMP_BAT%" >nul 2>&1
if errorlevel 1 (
    del "%TMP_BAT%" >nul 2>&1
    echo ERROR: nvcc build failed.
    popd
    exit /b 1
)
del "%TMP_BAT%" >nul 2>&1
echo       OK

echo [2/3] Building backend_loader.o...
set "CFLAGS=-D_FILE_OFFSET_BITS=64 -O3 -march=native -fopenmp -Wall -Wextra -Wno-unused-parameter -Wno-misleading-indentation -Wno-unused-function -DCOLI_CUDA"
"%GCC%" %CFLAGS% -c backend_loader.c -o backend_loader.o
if errorlevel 1 (
    echo ERROR: gcc failed on backend_loader.o
    popd
    exit /b 1
)
echo       OK

echo [3/3] Linking colibri.exe...
set "LDFLAGS=-lm -fopenmp -static -lpsapi"
"%GCC%" %CFLAGS% colibri.c backend_loader.o -o colibri.exe %LDFLAGS%
if errorlevel 1 (
    echo ERROR: gcc failed on colibri.exe
    popd
    exit /b 1
)
echo       OK

copy /y colibri.exe "%~dp0colibri.exe" >nul 2>&1
copy /y coli_cuda.dll "%~dp0coli_cuda.dll" >nul 2>&1
popd

echo.
echo ============================================================
echo  BUILD SUCCESS
echo  %~dp0colibri.exe
echo  %~dp0coli_cuda.dll
echo ============================================================
echo.
echo  Run: Run_Colibri.bat
echo  Toggles: CUDA GPU ON, CUDA Dense ON
echo.
pause
