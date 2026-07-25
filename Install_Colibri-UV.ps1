# ==========================================================
# colibri Portable Installer (v1.0.0)
# Author:  Soror L.'. L.'.
# ==========================================================
# Creates an isolated Python 3.12 venv with UV for the
# colibri DearPyGui control panel.
#
# USAGE:
#   .\Install_Colibri-UV.ps1              = interactive menu
#   .\Install_Colibri-UV.ps1 -Install     = full install (non-interactive)
#   .\Install_Colibri-UV.ps1 -Reinstall   = wipe & reinstall
#
#   Runtime (launch GUI) is handled by Run_Colibri.ps1.
# ==========================================================

param(
    [switch]$Install,
    [switch]$Reinstall,
    [switch]$Menu
)
$Script:CLI_MODE = ($Install -or $Reinstall)
if (-not $Script:CLI_MODE -and -not $Menu) { $Menu = $true }

$ScriptPath = $PSScriptRoot
if (-not $ScriptPath) { $ScriptPath = "." }
Set-Location $ScriptPath
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "colibri Portable Installer"

# ==============================================================
# ASCII Art
# ==============================================================
Write-Host " ===========================================	" -ForegroundColor Green
Write-Host ""
Write-Host "  ██▓        ██▓    ██▓        ██▓				" -ForegroundColor Yellow
Write-Host " ▓██▒              ▓██▒							" -ForegroundColor Yellow
Write-Host " ▒██░              ▒██░							" -ForegroundColor Yellow
Write-Host " ▒██░              ▒██░							" -ForegroundColor Yellow
Write-Host " ░██████▒ ██▓  ██▓ ░██████▒ ██▓  ██▓			" -ForegroundColor Yellow
Write-Host " ░ ▒░▓  ░ ▒▓▒  ▒▓▒ ░ ▒░▓  ░ ▒▓▒  ▒▓▒			" -ForegroundColor Yellow
Write-Host " ░ ░ ▒  ░ ░▒   ░▒  ░ ░ ▒  ░ ░▒   ░▒				" -ForegroundColor Yellow
Write-Host "   ░ ░    ░    ░     ░ ░    ░    ░				" -ForegroundColor Yellow
Write-Host "     ░  ░  ░    ░      ░  ░  ░    ░				" -ForegroundColor Yellow
Write-Host ""
Write-Host "  ===========================================	" -ForegroundColor Green
Write-Host "   colibri GLM-5.2 MoE Streaming Engine" -ForegroundColor Green
Write-Host "   GUI Portable Installer" -ForegroundColor Cyan

# ==========================================================
# PORTABILITY ISOLATION
# ==========================================================
$EnvName = "colibri_env"
$CacheDir = Join-Path $ScriptPath ".cache"
$UvCacheDir = Join-Path $CacheDir "uv"
$PipCacheDir = Join-Path $CacheDir "pip"
$TmpDir = Join-Path $CacheDir "tmp"

@($CacheDir, $UvCacheDir, $PipCacheDir, $TmpDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
}
$env:UV_CACHE_DIR = $UvCacheDir
$env:PIP_CACHE_DIR = $PipCacheDir
$env:TMP = $TmpDir
$env:TEMP = $TmpDir

function Write-Status {
    param([string]$Message, [string]$Type = "INFO")
    $color = switch ($Type) {
        "INFO"    { "Cyan" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host "[$Type] $Message" -ForegroundColor $color
}

function Test-IsInstalled {
    return (Test-Path (Join-Path $ScriptPath $EnvName "Scripts\python.exe"))
}

function Invoke-UvPipInstall {
    param([string]$Command)
    Write-Host "   > uv pip install $Command" -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $UvExePath -ArgumentList "pip install --python `"$PythonExePath`" $Command" -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Invoke-PythonCommand {
    param([string]$Command)
    Write-Host "   > python $Command" -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $PythonExePath -ArgumentList $Command -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

# ==========================================================
# INSTALL
# ==========================================================
function Install-Colibri {
    param([bool]$Reinstall = $false)

    if ($Reinstall) {
        Write-Status "Reinstall: removing existing environment..." "WARN"
        if (Test-Path $EnvName) { Remove-Item -LiteralPath $EnvName -Recurse -Force }
    }

    # ---- 0. Download uv ----
    $UvVersion = "0.11.6"
    $UvZipUrl = "https://releases.astral.sh/github/uv/releases/download/$UvVersion/uv-x86_64-pc-windows-msvc.zip"
    $UvExePath = Join-Path $ScriptPath "bin\uv.exe"

    if (-not (Test-Path $UvExePath)) {
        Write-Status "Downloading uv $UvVersion..." "INFO"
        $uvZip = Join-Path $ScriptPath "uv.zip"
        try { Invoke-WebRequest -Uri $UvZipUrl -OutFile $uvZip -ErrorAction Stop } catch {
            Write-Status "Failed to download uv: $_" "ERROR"
            return $false
        }
        if ((Get-Item $uvZip).Length -lt 1000) {
            Write-Status "Downloaded file corrupted." "ERROR"
            Remove-Item $uvZip -Force -ErrorAction SilentlyContinue
            return $false
        }
        $uvTmp = Join-Path $ScriptPath "uv_tmp"
        if (Test-Path $uvTmp) { Remove-Item -Recurse -Force $uvTmp }
        Expand-Archive -Path $uvZip -DestinationPath $uvTmp -Force
        $extractedDir = Get-ChildItem -Path $uvTmp -Directory | Select-Object -First 1
        if (-not $extractedDir) { $extractedDir = @{ FullName = $uvTmp } }
        Copy-Item (Join-Path $extractedDir.FullName "uv.exe") $UvExePath
        Copy-Item (Join-Path $extractedDir.FullName "uvx.exe") (Join-Path $ScriptPath "bin\uvx.exe") -ErrorAction SilentlyContinue
        Remove-Item $uvTmp -Recurse -Force
        Remove-Item $uvZip -Force
        Write-Status "uv $UvVersion ready." "SUCCESS"
    } else {
        Write-Status "uv already exists." "SUCCESS"
    }

    # ---- 0b. Download colibri engine (pre-built release from GitHub) ----
    $EngineVersion = "1.1.1"
    $EngineZipUrl = "https://github.com/JustVugg/colibri/releases/download/v$EngineVersion/colibri-v$EngineVersion-windows-x86_64.zip"
    $EngineZip = Join-Path $ScriptPath "colibri-release.zip"
    $EngineBinaries = @("colibri.exe", "coli", "openai_server.py", "resource_plan.py", "doctor.py", "version.py", "LICENSE")
    $AllBinariesPresent = ($EngineBinaries | ForEach-Object { Test-Path (Join-Path $ScriptPath $_) }) -notcontains $false

    if (-not $AllBinariesPresent -or $Reinstall) {
        Write-Status "Downloading colibri engine v$EngineVersion from GitHub..." "INFO"
        try {
            Invoke-WebRequest -Uri $EngineZipUrl -OutFile $EngineZip -ErrorAction Stop
        } catch {
            Write-Status "Failed to download colibri engine: $_" "WARN"
            Write-Status "You can download manually from: https://github.com/JustVugg/colibri/releases" "INFO"
        }
        if ((Test-Path $EngineZip) -and ((Get-Item $EngineZip).Length -gt 1000)) {
            $tmpDir = Join-Path $ScriptPath "_engine_tmp"
            if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
            Expand-Archive -Path $EngineZip -DestinationPath $tmpDir -Force
            Get-ChildItem -LiteralPath $tmpDir -Recurse | ForEach-Object {
                $rel = $_.FullName.Substring($tmpDir.Length + 1)
                $dest = Join-Path $ScriptPath $rel
                if ($_.PSIsContainer) {
                    New-Item -ItemType Directory -Force -Path $dest | Out-Null
                } else {
                    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
                }
            }
            Remove-Item -Recurse -Force $tmpDir
            Remove-Item $EngineZip -Force
            Write-Status "colibri engine v$EngineVersion installed." "SUCCESS"
        }
    } else {
        Write-Status "colibri engine already present." "SUCCESS"
    }

    # ---- 1. Create venv ----
    $EnvDirPath = Join-Path $ScriptPath $EnvName
    if (Test-Path $EnvDirPath) { Remove-Item -Recurse -Force $EnvDirPath }
    Write-Status "Creating virtual environment (Python 3.12)..." "INFO"
    & $UvExePath venv $EnvDirPath --python 3.12
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to create environment." "ERROR"
        return $false
    }
    $global:PythonExePath = Join-Path $EnvDirPath "Scripts\python.exe"
    Write-Status "Environment created." "SUCCESS"

    # ---- 2. Install dearpygui ----
    Write-Status "Installing dearpygui..." "INFO"
    if ((Invoke-UvPipInstall "dearpygui") -ne 0) {
        Write-Status "Failed to install dearpygui." "ERROR"
        return $false
    }
    Write-Status "dearpygui installed." "SUCCESS"

    # ---- 3. Install psutil (optional, for RAM monitoring) ----
    Write-Status "Installing psutil..." "INFO"
    Invoke-UvPipInstall "psutil"
    Write-Status "psutil installed." "SUCCESS"

    # ---- 4. Install pycurl (for model download) ----
    Write-Status "Installing pycurl..." "INFO"
    Invoke-UvPipInstall "pycurl certifi"

    # ---- 5. Clone colibri source (for Web UI, source reference) ----
    $SrcDir = Join-Path $ScriptPath "src\colibri"
    if (-not (Test-Path (Join-Path $SrcDir ".git"))) {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            if (Test-Path $SrcDir) { Remove-Item -Recurse -Force $SrcDir }
            Write-Status "Cloning colibri source from GitHub..." "INFO"
            git clone --depth 1 https://github.com/JustVugg/colibri.git $SrcDir 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Source cloned." "SUCCESS"
            } else {
                Write-Status "Git clone failed — Web UI will be unavailable." "WARN"
            }
        } else {
            Write-Status "Git not found — source skipped." "WARN"
        }
    } else {
        Write-Status "Source already cloned." "SUCCESS"
    }

    # ---- 6. Web UI (npm install) ----
    $WebDir = Join-Path $ScriptPath "src\colibri\web"
    if (Test-Path (Join-Path $WebDir "package.json")) {
        if (Get-Command node -ErrorAction SilentlyContinue) {
            $nodeModules = Join-Path $WebDir "node_modules"
            if (-not (Test-Path $nodeModules)) {
                Write-Status "Installing Web UI dependencies (npm)..." "INFO"
                Push-Location $WebDir
                npm install --legacy-peer-deps 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Status "Web UI ready (npm install OK)." "SUCCESS"
                } else {
                    Write-Status "npm install had issues — run manually: cd src\colibri\web && npm install" "WARN"
                }
                Pop-Location
            } else {
                Write-Status "Web UI already installed." "SUCCESS"
            }
        } else {
            Write-Status "Node.js not found — Web UI skipped. Install Node.js for the web chat interface." "WARN"
        }
    }

    Write-Status "Installation complete!" "SUCCESS"
    Write-Host ""
    Write-Status "Next: .\Run_Colibri.ps1    — launch the GUI" "INFO"
    Write-Status "Model: set COLI_MODEL or use GUI to download (~370 GB)" "INFO"
    if (-not (Test-Path (Join-Path $ScriptPath "coli_cuda.dll"))) {
        Write-Status "GPU: CPU-only binary — run .\build_cuda.ps1 for CUDA support" "WARN"
    }
    return $true
}

# ==========================================================
# MENU
# ==========================================================
function Show-Menu {
    Clear-Host
    Write-Host " ===========================================	" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ██▓        ██▓    ██▓        ██▓				" -ForegroundColor Yellow
    Write-Host " ▓██▒              ▓██▒							" -ForegroundColor Yellow
    Write-Host " ▒██░              ▒██░							" -ForegroundColor Yellow
    Write-Host " ▒██░              ▒██░							" -ForegroundColor Yellow
    Write-Host " ░██████▒ ██▓  ██▓ ░██████▒ ██▓  ██▓			" -ForegroundColor Yellow
    Write-Host " ░ ▒░▓  ░ ▒▓▒  ▒▓▒ ░ ▒░▓  ░ ▒▓▒  ▒▓▒			" -ForegroundColor Yellow
    Write-Host " ░ ░ ▒  ░ ░▒   ░▒  ░ ░ ▒  ░ ░▒   ░▒				" -ForegroundColor Yellow
    Write-Host "   ░ ░    ░    ░     ░ ░    ░    ░				" -ForegroundColor Yellow
    Write-Host "     ░  ░  ░    ░      ░  ░  ░    ░				" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ===========================================	" -ForegroundColor Green
    Write-Host "   colibri Portable Installer" -ForegroundColor Green
    Write-Host ""
    $installed = Test-IsInstalled
    if ($installed) {
        Write-Host "  Environment: INSTALLED" -ForegroundColor Green
        Write-Host ""
        Write-Host "  1) Reinstall (wipe and reinstall)" -ForegroundColor Yellow
        Write-Host "  2) Exit" -ForegroundColor Gray
    } else {
        Write-Host "  Environment: NOT INSTALLED" -ForegroundColor Red
        Write-Host ""
        Write-Host "  1) Install" -ForegroundColor Yellow
        Write-Host "  2) Exit" -ForegroundColor Gray
    }
    Write-Host ""
    $choice = Read-Host "Choice"
    return $choice, $installed
}

# ---- CLI dispatch ----
if ($Script:CLI_MODE) {
    $exitCode = 0
    try {
        if ($Install) {
            Write-Status "CLI: full install..." "INFO"
            Install-Colibri -Reinstall $false
            if (-not (Test-IsInstalled)) { throw "Installation failed." }
        }
        if ($Reinstall) {
            Write-Status "CLI: reinstall..." "INFO"
            Install-Colibri -Reinstall $true
            if (-not (Test-IsInstalled)) { throw "Reinstall failed." }
        }
    } catch {
        Write-Status "CLI ERROR: $_" "ERROR"
        $exitCode = 1
    }
    exit $exitCode
}

# ---- Interactive menu ----
do {
    $choice, $installed = Show-Menu
    switch ($choice) {
        "1" {
            if ($installed) {
                Install-Colibri -Reinstall $true
            } else {
                Install-Colibri -Reinstall $false
            }
            if (Test-IsInstalled) {
                Write-Status "Done! Run .\Run_Colibri.ps1 to start the GUI." "SUCCESS"
            }
            Read-Host "Press Enter to continue"
        }
        "2" { exit 0 }
        default { Write-Status "Invalid choice." "WARN" }
    }
} while ($true)
