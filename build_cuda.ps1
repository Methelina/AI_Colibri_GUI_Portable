# build_cuda.ps1 — colibri CUDA build (universal, interactive)
# Author:  Soror L.'. L.'.
# Auto-detects CUDA, gcc, MSVC, GPU arch. Asks user when ambiguous or missing.

$ErrorActionPreference = "Continue"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " colibri CUDA Build" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Prerequisites:" -ForegroundColor White
Write-Host "   - CUDA Toolkit (nvcc)" -ForegroundColor DarkGray
Write-Host "   - MinGW-w64 gcc + make" -ForegroundColor DarkGray
Write-Host "   - MSVC Build Tools (vcvars64.bat + cl.exe)" -ForegroundColor DarkGray
Write-Host ""

# ── Helpers ──
function Pick-One {
    param([string]$What, [string[]]$Items, [string]$Hint)
    if ($Items.Count -eq 0) {
        Write-Host "  $What not found." -ForegroundColor Red
        Write-Host "  $Hint" -ForegroundColor Yellow
        $manual = Read-Host "  Enter path manually (or Enter to abort)"
        if ($manual -and (Test-Path $manual)) { return @($manual) }
        return @()
    }
    if ($Items.Count -eq 1) {
        Write-Host "  $What : $($Items[0])" -ForegroundColor Green
        return $Items
    }
    Write-Host "  Multiple $What found:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host "    [$i] $($Items[$i])"
    }
    $choice = Read-Host "  Pick number (or Enter for [0])"
    if ($choice -eq "") { $choice = 0 }
    $idx = [int]$choice
    if ($idx -ge 0 -and $idx -lt $Items.Count) {
        return @($Items[$idx])
    }
    return @()
}

function Find-InStandardDirs {
    param([string[]]$Dirs, [string]$File)
    $found = @()
    foreach ($d in $Dirs) {
        if ($d -and (Test-Path (Join-Path $d $File))) {
            $found += Join-Path $d $File
        }
    }
    return $found
}

# ── 1. CUDA ──
$cudaCandidates = @()
# Check PATH first
if (Get-Command nvcc -ErrorAction SilentlyContinue) {
    $nvccPath = (Get-Command nvcc).Source
    $cudaHomeFromPath = Split-Path -Parent (Split-Path -Parent $nvccPath)
    if ($cudaHomeFromPath -and (Test-Path $cudaHomeFromPath)) {
        $cudaCandidates += $cudaHomeFromPath
    }
}
# Check standard install dirs
$cudaBase = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
if (Test-Path $cudaBase) {
    $cudaCandidates += @(Get-ChildItem $cudaBase -Directory |
        Where-Object { $_.Name -match '^v\d' } |
        Sort-Object Name -Descending |
        ForEach-Object { $_.FullName })
}
if ($env:CUDA_PATH -and (Test-Path $env:CUDA_PATH)) {
    $cudaCandidates = @($env:CUDA_PATH) + $cudaCandidates | Select-Object -Unique
}
$cudaCandidates = @($cudaCandidates | Select-Object -Unique)
$selected = Pick-One "CUDA Toolkit" $cudaCandidates "Install from: https://developer.nvidia.com/cuda-downloads"
if (-not $selected) { Write-Host "ABORTED: CUDA required." -ForegroundColor Red; exit 1 }
$CUDA_HOME = $selected[0]
$NVCC = Join-Path $CUDA_HOME "bin\nvcc.exe"

# ── 2. gcc (MinGW) ──
$gccDirs = @()
if (Get-Command gcc -ErrorAction SilentlyContinue) {
    $gccDirs += (Get-Command gcc).Source
}
$gccStdDirs = @(
    "C:\msys64\ucrt64\bin",
    "C:\msys64\mingw64\bin",
    "C:\mingw64\bin",
    "C:\MinGW\bin"
)
$gccDirs += Find-InStandardDirs $gccStdDirs "gcc.exe"
$gccDirs = @($gccDirs | Select-Object -Unique)
$selected = Pick-One "gcc (MinGW)" $gccDirs "Install: MSYS2 → pacman -S mingw-w64-ucrt-x86_64-gcc make     OR     scoop install mingw-winlibs"
if (-not $selected) { Write-Host "ABORTED: gcc required." -ForegroundColor Red; exit 1 }
$GCC = $selected[0]

# ── 3. MSVC (vcvars64.bat) ──
$vsDirs = @()
$vsStdDirs = @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build",
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build"
)
$vsDirs += Find-InStandardDirs $vsStdDirs "vcvars64.bat"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPaths = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPaths) {
        foreach ($p in @($vsPaths)) {
            $c = Join-Path $p "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $c) { $vsDirs += $c }
        }
    }
}
$vsDirs = @($vsDirs | Select-Object -Unique)
$selected = Pick-One "MSVC (vcvars64.bat)" $vsDirs "Install: winget install Microsoft.VisualStudio.2022.BuildTools     (select 'Desktop development with C++' workload)"
if (-not $selected) { Write-Host "ABORTED: MSVC required." -ForegroundColor Red; exit 1 }
$VCVARS = $selected[0]

# ── 4. GPU architecture ──
$CUDA_ARCH = $null
try {
    $smi = & nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1
    if ($smi) {
        $smi = $smi.Trim()
        if    ($smi -match "RTX 50|Blackwell")    { $CUDA_ARCH = "sm_120" }
        elseif ($smi -match "RTX 4090|RTX 4080|RTX 4070|RTX 4060|Ada") { $CUDA_ARCH = "sm_89" }
        elseif ($smi -match "RTX 3090|RTX 3080|RTX 3070|RTX 3060|Ampere|A\d000|A100") { $CUDA_ARCH = "sm_86" }
        elseif ($smi -match "RTX 20|Turing|T4|Quadro RTX") { $CUDA_ARCH = "sm_75" }
        elseif ($smi -match "GTX 16|GTX 10|Pascal|P\d000|P100") { $CUDA_ARCH = "sm_61" }
        if ($CUDA_ARCH) {
            Write-Host "  GPU   : $smi → $CUDA_ARCH" -ForegroundColor Green
        }
    }
} catch {}
if (-not $CUDA_ARCH) {
    $CUDA_ARCH = Read-Host "  Enter CUDA arch (e.g. sm_86 for RTX 3060) [native]"
    if (-not $CUDA_ARCH) { $CUDA_ARCH = "native" }
}

# ── 5. Build ──
$SRC_DIR = Join-Path $PSScriptRoot "src\colibri\c"
$OUT_DIR = $PSScriptRoot

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Build config" -ForegroundColor Cyan
Write-Host "  CUDA:  $CUDA_HOME" -ForegroundColor White
Write-Host "  Arch:  $CUDA_ARCH" -ForegroundColor White
Write-Host "  gcc:   $GCC" -ForegroundColor White
Write-Host "  MSVC:  $VCVARS" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

if (-not (Test-Path $SRC_DIR)) { Write-Host "ERROR: src\colibri\c not found" -ForegroundColor Red; exit 1 }

$CFLAGS = "-D_FILE_OFFSET_BITS=64 -O3 -march=native -fopenmp -Wall -Wextra -Wno-unused-parameter -Wno-misleading-indentation -Wno-unused-function -DCOLI_CUDA"
$LDFLAGS = "-lm -fopenmp -static -lpsapi"

Push-Location $SRC_DIR
try {
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
    $tmpBat = Join-Path $PSScriptRoot "_build_cuda_tmp.bat"
    [IO.File]::WriteAllText($tmpBat, ($cmds -join "`r`n"), [Text.Encoding]::ASCII)
    $result = cmd /c "`"$tmpBat`" 2>&1"
    Remove-Item $tmpBat -Force -ErrorAction SilentlyContinue
    if ($result -match "VCVARS_FAILED") { throw "vcvars64.bat failed" }
    if ($result -match "NVCC_FAILED") { throw "nvcc failed" }
    Write-Host "       OK" -ForegroundColor Green

    Write-Host "`n[2/3] Building backend_loader.o (gcc)..." -ForegroundColor Yellow
    & $GCC ($CFLAGS.Split(" ") + @("-c", "backend_loader.c", "-o", "backend_loader.o"))
    if ($LASTEXITCODE -ne 0) { throw "gcc failed on backend_loader.o" }
    Write-Host "       OK" -ForegroundColor Green

    Write-Host "`n[3/3] Linking colibri.exe (gcc + CUDA loader)..." -ForegroundColor Yellow
    & $GCC ($CFLAGS.Split(" ") + @("colibri.c", "backend_loader.o", "-o", "colibri.exe") + $LDFLAGS.Split(" "))
    if ($LASTEXITCODE -ne 0) { throw "gcc failed on colibri.exe" }
    Write-Host "       OK" -ForegroundColor Green

    Copy-Item -Path "colibri.exe" -Destination (Join-Path $OUT_DIR "colibri.exe") -Force
    Copy-Item -Path "coli_cuda.dll" -Destination (Join-Path $OUT_DIR "coli_cuda.dll") -Force
} finally {
    Pop-Location
}

if ((Test-Path (Join-Path $OUT_DIR "colibri.exe")) -and (Test-Path (Join-Path $OUT_DIR "coli_cuda.dll"))) {
    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host " BUILD SUCCESS" -ForegroundColor Green
    Write-Host " $OUT_DIR\colibri.exe  (CUDA-enabled)" -ForegroundColor White
    Write-Host " $OUT_DIR\coli_cuda.dll" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Run: .\Run_Colibri.ps1" -ForegroundColor White
    Write-Host "  Toggles: CUDA GPU ON, CUDA Dense ON" -ForegroundColor White
} else {
    Write-Host "ERROR: Copy to root failed" -ForegroundColor Red
    exit 1
}
