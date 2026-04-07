param(
    [string]$PackageDir = "",
    [string]$PluginDir = "",
    [string]$DistroName = "",
    [string]$InstallDir = "",
    [switch]$ReplaceExisting,
    [switch]$SkipCopyToPluginDir
)

$ErrorActionPreference = 'Stop'

function Get-ScriptDir {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return (Split-Path -Parent $PSCommandPath)
    }
    if ($MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }
    return (Get-Location).Path
}

function Convert-FileToLf([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) {
        return
    }

    $content = [System.IO.File]::ReadAllText($Path)
    $content = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Copy-IfExists([string]$Source, [string]$Destination) {
    if (Test-Path $Source) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -Force $Source $Destination
    }
}

function Sync-Directory([string]$SourceDir, [string]$DestinationDir) {
    if (!(Test-Path $SourceDir)) {
        return
    }
    if (Test-Path $DestinationDir) {
        Remove-Item -Recurse -Force $DestinationDir
    }
    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    Copy-Item -Recurse -Force (Join-Path $SourceDir '*') $DestinationDir
}

function Resolve-DistroName([string]$Dir, [string]$Current) {
    if (-not [string]::IsNullOrWhiteSpace($Current)) {
        return $Current
    }

    $distroFile = Join-Path $Dir 'pjarczak_wsl_distro.txt'
    if (Test-Path $distroFile) {
        $value = (Get-Content $distroFile -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    if ($env:PJARCZAK_WSL_DISTRO) {
        return $env:PJARCZAK_WSL_DISTRO.Trim()
    }

    return 'PJARCZAK-BAMBU'
}

$scriptDir = Get-ScriptDir
$defaultPackageDir = $scriptDir
if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $defaultPackageDir
}
$PackageDir = [System.IO.Path]::GetFullPath($PackageDir)

$DistroName = Resolve-DistroName $PackageDir $DistroName

if ([string]::IsNullOrWhiteSpace($PluginDir)) {
    if (-not $env:APPDATA) {
        throw 'APPDATA is not available'
    }
    $PluginDir = Join-Path $env:APPDATA 'OrcaSlicer\plugins'
}
$PluginDir = [System.IO.Path]::GetFullPath($PluginDir)

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if (-not $env:LOCALAPPDATA) {
        throw 'LOCALAPPDATA is not available'
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA $DistroName
}
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)

$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
if (!(Test-Path $wsl)) {
    throw 'wsl.exe not found'
}

if (-not $SkipCopyToPluginDir) {
    New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null

    $fileNames = @(
        'pjarczak_bambu_networking_bridge.dll',
        'pjarczak_bambu_linux_host',
        'pjarczak_wsl_distro.txt',
        'pjarczak_wsl_run_host.sh',
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
        'libagora-fdkaac.so'
    )

    foreach ($name in $fileNames) {
        Copy-IfExists (Join-Path $PackageDir $name) (Join-Path $PluginDir $name)
    }

    Sync-Directory (Join-Path $PackageDir 'pjarczak_bambu_linux_host.runtime') (Join-Path $PluginDir 'pjarczak_bambu_linux_host.runtime')
    $PackageDir = $PluginDir
}

$requiredFiles = @(
    'pjarczak_bambu_networking_bridge.dll',
    'pjarczak_bambu_linux_host',
    'pjarczak_wsl_distro.txt',
    'pjarczak_wsl_run_host.sh',
    'install_runtime.ps1',
    'verify_runtime.ps1',
    'windows-wsl2-rootfs.tar'
)

foreach ($name in $requiredFiles) {
    $path = Join-Path $PackageDir $name
    if (!(Test-Path $path)) {
        throw "Missing package file: $name"
    }
}

try {
    & $wsl --status | Out-Null
} catch {
    throw 'WSL is not ready. Run as Administrator once and execute: wsl --install --no-distribution ; wsl --update ; then reboot.'
}

Convert-FileToLf (Join-Path $PackageDir 'pjarczak_wsl_run_host.sh')

$distroList = & $wsl -l -q 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to query installed WSL distros'
}

$alreadyInstalled = $distroList | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $DistroName }
if ($alreadyInstalled) {
    if ($ReplaceExisting) {
        & $wsl --terminate $DistroName 2>$null | Out-Null
        & $wsl --unregister $DistroName
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to unregister existing distro '$DistroName'"
        }
        $alreadyInstalled = $null
    }
}

if (-not $alreadyInstalled) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $rootFsTar = Join-Path $PackageDir 'windows-wsl2-rootfs.tar'
    & $wsl --import $DistroName $InstallDir $rootFsTar --version 2
    if ($LASTEXITCODE -ne 0) {
        throw "wsl --import failed for distro '$DistroName'"
    }

    $wslConf = @'
[automount]
enabled=true
root=/mnt/
mountFsTab=false

[interop]
enabled=true
appendWindowsPath=false
'@

    $setupCmd = @"
cat > /etc/wsl.conf <<'WSL_EOF'
$wslConf
WSL_EOF
mkdir -p /root/.pjarczak-bambu-runtime
"@

    & $wsl -d $DistroName --user root -- sh -lc $setupCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to initialize distro '$DistroName'"
    }

    & $wsl --terminate $DistroName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to terminate distro '$DistroName' after initialization"
    }
}

$verifyArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PackageDir 'verify_runtime.ps1'),
    '-PackageDir', $PackageDir,
    '-DistroName', $DistroName,
    '-PluginCacheDir', $PluginDir,
    '-AllowMissingLinuxPlugin'
)

& powershell @verifyArgs
if ($LASTEXITCODE -ne 0) {
    throw 'verify_runtime.ps1 failed'
}

Write-Host ''
Write-Host "WSL runtime installed to: $PackageDir"
Write-Host "WSL distro: $DistroName"
Write-Host "WSL install dir: $InstallDir"
Write-Host 'Now start OrcaSlicer.'
Write-Host 'On first run let it download bambunetwork, close the app completely, then start it again.'
