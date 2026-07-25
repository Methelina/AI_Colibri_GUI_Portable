# colibri v1.1.0 - GLM-5.2 MoE Control Panel Launcher
# Author:  Soror L.'. L.'.
# Default: launches DearPyGui control panel.
#
# USAGE:
#   .\Run_Colibri.ps1                    = launch GUI
#   .\Run_Colibri.ps1 -Serve             = start API server
#   .\Run_Colibri.ps1 -StopServe         = stop API server
#   .\Run_Colibri.ps1 -Chat              = launch interactive chat
#   .\Run_Colibri.ps1 -Run "<prompt>"    = one-shot generation
#   .\Run_Colibri.ps1 -Doctor            = health check
#   .\Run_Colibri.ps1 -Plan              = resource plan

param(
    [switch]$Serve,
    [switch]$StopServe,
    [switch]$Chat,
    [string]$Run = "",
    [switch]$Doctor,
    [switch]$Plan,
    [switch]$Cleanup
)
$Script:CLI_MODE = ($Serve -or $StopServe -or $Chat -or $Run -or $Doctor -or $Plan -or $Cleanup)

$ScriptPath = $PSScriptRoot
if (-not $ScriptPath) { $ScriptPath = "." }
Set-Location $ScriptPath
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "colibri - GLM-5.2 MoE Streaming"

$EnvDir = Join-Path $ScriptPath "colibri_env"
$PythonExe = Join-Path $EnvDir "Scripts\python.exe"

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
    return (Test-Path $PythonExe)
}

function Invoke-Ctl {
    param([string[]]$CtlArgs)
    & $PythonExe (Join-Path $ScriptPath "scripts\colibri_ctl.py") @CtlArgs
    return $LASTEXITCODE
}

# ---- CLI dispatch ----
if ($Script:CLI_MODE) {
    $exitCode = 0
    try {
        if (-not (Test-IsInstalled)) {
            throw "Environment not installed. Run .\Install_Colibri-UV.ps1 -Install first."
        }
        if ($Serve) {
            Write-Status "Starting serve..." "INFO"
            Invoke-Ctl @("serve")
        }
        if ($StopServe) {
            Write-Status "Stopping serve..." "INFO"
            Invoke-Ctl @("stop")
        }
        if ($Chat) {
            Write-Status "Launching chat..." "INFO"
            $model = $env:COLI_MODEL
            $args = @("serve") # chat is not a ctl command, handled by GUI
            Write-Status "Use GUI for chat, or run: python coli chat --model $model" "WARN"
        }
        if ($Run) {
            Write-Status "Running: $Run" "INFO"
            Invoke-Ctl @("run", $Run)
        }
        if ($Doctor) {
            Write-Status "Running doctor..." "INFO"
            Invoke-Ctl @("doctor")
        }
        if ($Plan) {
            Write-Status "Running plan..." "INFO"
            Invoke-Ctl @("plan")
        }
        if ($Cleanup) {
            Write-Status "Cleaning up..." "INFO"
            Invoke-Ctl @("cleanup")
        }
    } catch {
        Write-Status "CLI ERROR: $_" "ERROR"
        $exitCode = 1
    }
    exit $exitCode
}

# ---- Default: launch GUI ----
if (-not (Test-IsInstalled)) {
    Write-Status "Environment not installed." "ERROR"
    Write-Status "Run .\Install_Colibri-UV.ps1 -Install first." "INFO"
    Read-Host "Press Enter to exit"
    exit 1
}

$GuiScript = Join-Path $ScriptPath "scripts\colibri_gui.py"
if (-not (Test-Path $GuiScript)) {
    Write-Status "GUI script not found: $GuiScript" "ERROR"
    exit 1
}

# Set model path for the GUI session
$modelPath = $env:COLI_MODEL
if (-not $modelPath) {
    $guesses = @(
        "D:\glm52_i4",
        "E:\glm52_i4",
        (Join-Path $ScriptPath "glm52_i4")
    )
    foreach ($g in $guesses) {
        if (Test-Path $g) {
            $env:COLI_MODEL = $g
            $env:SNAP = $g
            Write-Status "Auto-detected model: $g" "INFO"
            break
        }
    }
}

Write-Status "Launching colibri GUI..." "SUCCESS"
& $PythonExe $GuiScript
exit $LASTEXITCODE
