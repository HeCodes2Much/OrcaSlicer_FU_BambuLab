param(
    [string]$PackageDir = "",
    [string]$PluginDir = "",
    [string]$DistroName = "",
    [string]$InstallDir = "",
    [switch]$ReplaceExisting,
    [switch]$SkipCopyToPluginDir,
    [switch]$CoreInstallOnly
)

$ErrorActionPreference = 'Stop'

function Get-ScriptDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    return (Get-Location).Path
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Native([string]$FilePath, [string[]]$ArgumentList) {
    & $FilePath @ArgumentList
    return $LASTEXITCODE
}

function Convert-FileToLf([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return }
    $content = [System.IO.File]::ReadAllText($Path)
    $content = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Copy-IfExists([string]$Source, [string]$Destination) {
    if (!(Test-Path $Source)) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -Force $Source $Destination
}

function Resolve-DistroName([string]$BaseDir, [string]$Current) {
    if (-not [string]::IsNullOrWhiteSpace($Current)) { return $Current }
    if ($env:PJARCZAK_WSL_DISTRO) { return $env:PJARCZAK_WSL_DISTRO.Trim() }
    $distroFile = Join-Path $BaseDir 'pjarczak_wsl_distro.txt'
    if (Test-Path $distroFile) {
        $value = (Get-Content $distroFile -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return 'BambuBridge-OrcaSlicer'
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = Get-ScriptDir
}
$PackageDir = [System.IO.Path]::GetFullPath($PackageDir)

if ([string]::IsNullOrWhiteSpace($PluginDir)) {
    if (-not $env:APPDATA) { throw 'APPDATA is not available' }
    $PluginDir = Join-Path $env:APPDATA 'OrcaSlicer\plugins'
}
$PluginDir = [System.IO.Path]::GetFullPath($PluginDir)

$PluginCacheDir = if ($env:APPDATA) { Join-Path $env:APPDATA 'OrcaSlicer\ota' } else { '' }
$DistroName = Resolve-DistroName $PackageDir $DistroName

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not available' }
    $InstallDir = Join-Path $env:LOCALAPPDATA $DistroName
}
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)

$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
if (!(Test-Path $wsl)) {
    throw 'wsl.exe not found. This Windows build does not expose WSL commands.'
}

$bootstrapPath = Join-Path $PackageDir 'pjarczak_wsl_run_host.sh'
if (Test-Path $bootstrapPath) {
    Convert-FileToLf $bootstrapPath
}

$packageFiles = @(
    'pjarczak_bambu_linux_host',
    'pjarczak_bambu_linux_host_abi1',
    'pjarczak_bambu_linux_host_abi0',
    'pjarczak_wsl_run_host.sh',
    'pjarczak_wsl_distro.txt',
    'install_runtime.ps1',
    'install_runtime.cmd',
    'verify_runtime.ps1',
    'windows-wsl2-rootfs.tar'
)
foreach ($name in $packageFiles) {
    if (!(Test-Path (Join-Path $PackageDir $name))) {
        throw "Missing package file: $name"
    }
}

if (-not $SkipCopyToPluginDir) {
    New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null
    $copyNames = @(
        'pjarczak_bambu_networking_bridge.dll',
        'pjarczak_bambu_linux_host',
        'pjarczak_bambu_linux_host_abi1',
        'pjarczak_bambu_linux_host_abi0',
        'pjarczak_wsl_run_host.sh',
        'pjarczak_wsl_distro.txt',
        'install_runtime.ps1',
        'install_runtime.cmd',
        'verify_runtime.ps1',
        'windows-wsl2-rootfs.tar',
        'README_runtime_bridge.txt',
        'assemble_windows_runtime_bundle.ps1',
        'linux_payload_manifest.json',
        'libbambu_networking.so',
        'libBambuSource.so',
        'liblive555.so',
        'libagora_rtc_sdk.so',
        'libagora-fdkaac.so',
        'libz.so.1',
        'libzstd.so.1',
        'libcrypto.so.3',
        'libstdc++.so.6',
        'libgcc_s.so.1',
        'ca-certificates.crt',
        'slicer_base64.cer'
    )
    foreach ($name in $copyNames) {
        Copy-IfExists (Join-Path $PackageDir $name) (Join-Path $PluginDir $name)
    }
    $PackageDir = $PluginDir
}

$needCoreInstall = $false
try {
    & $wsl --status | Out-Null
    if ($LASTEXITCODE -ne 0) { $needCoreInstall = $true }
} catch {
    $needCoreInstall = $true
}

if ($needCoreInstall -and -not (Test-IsAdmin)) {
    $self = Join-Path $PackageDir 'install_runtime.ps1'
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $self + '"'),
        '-PackageDir', ('"' + $PackageDir + '"'),
        '-PluginDir', ('"' + $PluginDir + '"'),
        '-DistroName', ('"' + $DistroName + '"'),
        '-InstallDir', ('"' + $InstallDir + '"'),
        '-SkipCopyToPluginDir',
        '-CoreInstallOnly'
    )
    $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0) { exit $proc.ExitCode }
    $needCoreInstall = $false
}

$rebootRequired = $false
if ($needCoreInstall) {
    Write-Host 'Installing or enabling WSL core components'
    $code = Invoke-Native $wsl @('--install', '--no-distribution')
    if ($code -eq 1641 -or $code -eq 3010) {
        $rebootRequired = $true
    } elseif ($code -ne 0) {
        throw "wsl --install --no-distribution failed with exit code $code"
    }
    $code = Invoke-Native $wsl @('--set-default-version', '2')
    if ($code -ne 0) { throw "wsl --set-default-version 2 failed with exit code $code" }
    $code = Invoke-Native $wsl @('--update')
    if ($code -ne 0) { throw "wsl --update failed with exit code $code" }
}

if ($rebootRequired) {
    Write-Host 'WSL install requested a reboot.'
    exit 3010
}

if ($CoreInstallOnly) {
    exit 0
}

& $wsl --status | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'WSL is still not ready after install/update'
}

$distroList = & $wsl -l -q 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to query installed WSL distros'
}
$hasDistro = ($distroList | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $DistroName })

if ($hasDistro -and $ReplaceExisting) {
    & $wsl --terminate $DistroName 2>$null | Out-Null
    & $wsl --unregister $DistroName
    if ($LASTEXITCODE -ne 0) { throw "Failed to unregister existing distro '$DistroName'" }
    $hasDistro = $false
}

if (-not $hasDistro) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $rootFsTar = Join-Path $PackageDir 'windows-wsl2-rootfs.tar'
    & $wsl --import $DistroName $InstallDir $rootFsTar --version 2
    if ($LASTEXITCODE -ne 0) { throw "wsl --import failed for distro '$DistroName'" }

    $setupCmd = @"
cat > /etc/wsl.conf <<'WSL_EOF'
[automount]
enabled=true
root=/mnt/
mountFsTab=false

[interop]
enabled=true
appendWindowsPath=false
WSL_EOF
mkdir -p /root/.pjarczak-bambu-runtime
"@
    & $wsl -d $DistroName --user root -- sh -lc $setupCmd
    if ($LASTEXITCODE -ne 0) { throw "Failed to initialize distro '$DistroName'" }
    & $wsl --terminate $DistroName
    if ($LASTEXITCODE -ne 0) { throw "Failed to terminate distro '$DistroName' after initialization" }
}

$verifyArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PackageDir 'verify_runtime.ps1'),
    '-PackageDir', $PackageDir,
    '-DistroName', $DistroName,
    '-PluginCacheDir', $PluginCacheDir,
    '-AllowMissingLinuxPlugin',
    '-SkipProbe'
)
& powershell.exe @verifyArgs
if ($LASTEXITCODE -ne 0) {
    throw 'verify_runtime.ps1 failed'
}

Write-Host ''
Write-Host "WSL runtime installed to: $PackageDir"
Write-Host "WSL distro: $DistroName"
Write-Host "WSL install dir: $InstallDir"
Write-Host 'On first run let Orca download bambunetwork if needed, then restart Orca.'
