# build_cuda.ps1 — colibri CUDA build for RTX 3060 (sm_86)
# Author:  Soror L.'. L.'.
# Direct nvcc + gcc, no Makefile needed

$ErrorActionPreference = "Stop"

$CUDA_HOME = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$NVCC      = "$CUDA_HOME\bin\nvcc.exe"
$GCC       = "O:\Work\Coding\QT\Tools\mingw1310_64\bin\gcc.exe"
$VCVARS    = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
$SRC_DIR   = Join-Path $PSScriptRoot "src\colibri\c"
$OUT_DIR   = $PSScriptRoot
$CUDA_ARCH = "sm_86"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " colibri CUDA Build" -ForegroundColor Cyan
Write-Host " CUDA:  $CUDA_HOME" -ForegroundColor White
Write-Host " Arch:  $CUDA_ARCH (RTX 3060 Ampere)" -ForegroundColor White
Write-Host " gcc:   $GCC" -ForegroundColor White
Write-Host " Src:   $SRC_DIR" -ForegroundColor White
Write-Host " Out:   $OUT_DIR" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

if (-not (Test-Path $NVCC))  { Write-Host "ERROR: nvcc not found at $NVCC" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $GCC))   { Write-Host "ERROR: gcc not found at $GCC"  -ForegroundColor Red; exit 1 }
if (-not (Test-Path $VCVARS)) { Write-Host "ERROR: vcvars64.bat not found at $VCVARS" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $SRC_DIR)) { Write-Host "ERROR: src dir not found at $SRC_DIR" -ForegroundColor Red; exit 1 }

# Build a single cmd /c command that chains: vcvars -> set PATH -> nvcc
# Everything runs in ONE cmd session so env vars persist.

# CFLAGS for gcc
$CFLAGS = "-D_FILE_OFFSET_BITS=64 -O3 -march=native -fopenmp -Wall -Wextra -Wno-unused-parameter -Wno-misleading-indentation -Wno-unused-function -DCOLI_CUDA"
$LDFLAGS = "-lm -fopenmp -static -lpsapi"

Push-Location $SRC_DIR
try {
    # === STEP 1: Build coli_cuda.dll ===
    Write-Host "`n[1/3] Building coli_cuda.dll (nvcc + MSVC)..." -ForegroundColor Yellow

    $cmds = @(
        '@echo off',
        "call `"$VCVARS`" >nul 2>&1",
        'if errorlevel 1 echo VCVARS_FAILED & exit /b 1',
        "set PATH=$CUDA_HOME\bin;%PATH%",
        "`"$NVCC`" -O3 -std=c++17 -arch=$CUDA_ARCH -Xcompiler=-W3 -shared -DCOLI_CUDA_BUILDING_DLL -L`"$CUDA_HOME\lib\x64`" -lcudart backend_cuda.cu -o coli_cuda.dll",
        'if errorlevel 1 echo NVCC_FAILED & exit /b 1',
        'echo NVCC_OK'
    )
    $batContent = $cmds -join "`r`n"
    $tmpBat = Join-Path $PSScriptRoot "_build_cuda_tmp.bat"
    [System.IO.File]::WriteAllText($tmpBat, $batContent, [System.Text.Encoding]::ASCII)

    $result = cmd /c "`"$tmpBat`" 2>&1"
    Remove-Item $tmpBat -Force -ErrorAction SilentlyContinue

    if ($result -match "VCVARS_FAILED" -or $LASTEXITCODE -ne 0) {
        Write-Host "ERROR: vcvars64.bat failed" -ForegroundColor Red
        Write-Host $result
        Pop-Location; exit 1
    }
    if ($result -match "NVCC_FAILED") {
        Write-Host "ERROR: nvcc failed" -ForegroundColor Red
        Write-Host $result
        Pop-Location; exit 1
    }
    Write-Host "       coli_cuda.dll OK" -ForegroundColor Green

    # === STEP 2: Build backend_loader.o ===
    Write-Host "`n[2/3] Building backend_loader.o (gcc)..." -ForegroundColor Yellow
    $gccArgs = $CFLAGS.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries) + @("-c", "backend_loader.c", "-o", "backend_loader.o")
    & $GCC $gccArgs
    if ($LASTEXITCODE -ne 0) { throw "gcc failed on backend_loader.o" }
    Write-Host "       backend_loader.o OK" -ForegroundColor Green

    # === STEP 3: Link colibri.exe ===
    Write-Host "`n[3/3] Linking colibri.exe (gcc + CUDA loader)..." -ForegroundColor Yellow
    $gccArgs = $CFLAGS.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries) + @("colibri.c", "backend_loader.o", "-o", "colibri.exe") + $LDFLAGS.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    & $GCC $gccArgs
    if ($LASTEXITCODE -ne 0) { throw "gcc failed on colibri.exe link" }
    Write-Host "       colibri.exe OK" -ForegroundColor Green

    # === Copy to root ===
    Copy-Item -LiteralPath "colibri.exe" -Destination (Join-Path $OUT_DIR "colibri.exe") -Force
    Copy-Item -LiteralPath "coli_cuda.dll" -Destination (Join-Path $OUT_DIR "coli_cuda.dll") -Force

} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Pop-Location; exit 1
}
Pop-Location

if ((Test-Path (Join-Path $OUT_DIR "colibri.exe")) -and (Test-Path (Join-Path $OUT_DIR "coli_cuda.dll"))) {
    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host " BUILD SUCCESS" -ForegroundColor Green
    Write-Host " $OUT_DIR\colibri.exe  (CUDA-enabled)" -ForegroundColor White
    Write-Host " $OUT_DIR\coli_cuda.dll" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Run: .\Run_Colibri.ps1" -ForegroundColor White
    Write-Host "  Toggles to enable: CUDA GPU, CUDA Dense" -ForegroundColor White
} else {
    Write-Host "ERROR: Copy to root failed" -ForegroundColor Red
    exit 1
}
