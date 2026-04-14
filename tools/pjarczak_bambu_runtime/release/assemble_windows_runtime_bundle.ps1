param(
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [Parameter(Mandatory = $true)][string]$RootFs,
    [Parameter(Mandatory = $true)][string]$LinuxHostAbi1,
    [Parameter(Mandatory = $true)][string]$LinuxHostAbi0,
    [string]$LinuxHostWrapper = "",
    [string]$BridgeDll = "",
    [string]$DistroName = "PJARCZAK-BAMBU"
)

$ErrorActionPreference = 'Stop'

function Get-ScriptDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    return (Get-Location).Path
}

$scriptDir = Get-ScriptDir
$toolsRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
$wslRoot = Join-Path $toolsRoot 'wsl'

if (-not (Test-Path $RootFs)) { throw "RootFs not found: $RootFs" }
if (-not (Test-Path $LinuxHostAbi1)) { throw "LinuxHostAbi1 not found: $LinuxHostAbi1" }
if (-not (Test-Path $LinuxHostAbi0)) { throw "LinuxHostAbi0 not found: $LinuxHostAbi0" }
if ([string]::IsNullOrWhiteSpace($LinuxHostWrapper)) {
    $LinuxHostWrapper = Join-Path $wslRoot 'pjarczak_bambu_linux_host'
}
if (-not (Test-Path $LinuxHostWrapper)) { throw "LinuxHostWrapper not found: $LinuxHostWrapper" }
if ($BridgeDll -and -not (Test-Path $BridgeDll)) { throw "BridgeDll not found: $BridgeDll" }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Copy-Item -Force (Join-Path $wslRoot 'install_runtime.ps1') (Join-Path $OutputDir 'install_runtime.ps1')
Copy-Item -Force (Join-Path $wslRoot 'install_runtime.cmd') (Join-Path $OutputDir 'install_runtime.cmd')
Copy-Item -Force (Join-Path $wslRoot 'verify_runtime.ps1') (Join-Path $OutputDir 'verify_runtime.ps1')
Copy-Item -Force (Join-Path $wslRoot 'pjarczak_wsl_run_host.sh') (Join-Path $OutputDir 'pjarczak_wsl_run_host.sh')
Copy-Item -Force (Join-Path $wslRoot 'pjarczak_wsl_distro.txt') (Join-Path $OutputDir 'pjarczak_wsl_distro.txt')

Set-Content -Path (Join-Path $OutputDir 'pjarczak_wsl_distro.txt') -Value ($DistroName + [Environment]::NewLine) -NoNewline:$false

Copy-Item -Force $RootFs (Join-Path $OutputDir 'windows-wsl2-rootfs.tar')
Copy-Item -Force $LinuxHostWrapper (Join-Path $OutputDir 'pjarczak_bambu_linux_host')
Copy-Item -Force $LinuxHostAbi1 (Join-Path $OutputDir 'pjarczak_bambu_linux_host_abi1')
Copy-Item -Force $LinuxHostAbi0 (Join-Path $OutputDir 'pjarczak_bambu_linux_host_abi0')

if ($BridgeDll) {
    Copy-Item -Force $BridgeDll (Join-Path $OutputDir 'pjarczak_bambu_networking_bridge.dll')
}

Write-Host 'Bundle created:'
Write-Host $OutputDir
