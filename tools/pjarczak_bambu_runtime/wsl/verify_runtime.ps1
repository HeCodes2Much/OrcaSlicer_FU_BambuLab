param(
    [string]$PackageDir = "",
    [string]$DistroName = "",
    [string]$PluginCacheDir = "",
    [switch]$AllowMissingLinuxPlugin,
    [switch]$SkipProbe
)

$ErrorActionPreference = 'Stop'

function Get-ScriptDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    return (Get-Location).Path
}

function Convert-FileToLf([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) { return }
    $content = [System.IO.File]::ReadAllText($Path)
    $content = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function To-WslPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -ge 2 -and $full[1] -eq ':') {
        $drive = $full.Substring(0, 1).ToLowerInvariant()
        $tail = $full.Substring(2).Replace('\', '/')
        if ($tail.StartsWith('/')) { $tail = $tail.Substring(1) }
        return "/mnt/$drive/$tail"
    }
    return $full.Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = Get-ScriptDir
}
$PackageDir = [System.IO.Path]::GetFullPath($PackageDir)

if ([string]::IsNullOrWhiteSpace($PluginCacheDir)) {
    if ($env:PJARCZAK_BAMBU_WINDOWS_PLUGIN_CACHE_DIR) {
        $PluginCacheDir = $env:PJARCZAK_BAMBU_WINDOWS_PLUGIN_CACHE_DIR
    } elseif ($env:APPDATA) {
        $PluginCacheDir = Join-Path $env:APPDATA 'OrcaSlicer\ota'
    }
}
if (-not [string]::IsNullOrWhiteSpace($PluginCacheDir)) {
    $PluginCacheDir = [System.IO.Path]::GetFullPath($PluginCacheDir)
}

if ([string]::IsNullOrWhiteSpace($DistroName)) {
    if ($env:PJARCZAK_WSL_DISTRO) {
        $DistroName = $env:PJARCZAK_WSL_DISTRO.Trim()
    } else {
        $distroFile = Join-Path $PackageDir 'pjarczak_wsl_distro.txt'
        if (Test-Path $distroFile) {
            $DistroName = (Get-Content $distroFile -Raw).Trim()
        }
    }
}
if ([string]::IsNullOrWhiteSpace($DistroName)) {
    throw 'Missing distro name. Set PJARCZAK_WSL_DISTRO or provide pjarczak_wsl_distro.txt.'
}

$requiredFiles = @(
    'pjarczak_wsl_distro.txt',
    'install_runtime.ps1',
    'verify_runtime.ps1',
    'pjarczak_wsl_run_host.sh',
    'pjarczak_bambu_linux_host',
    'pjarczak_bambu_linux_host_abi1',
    'pjarczak_bambu_linux_host_abi0',
    'windows-wsl2-rootfs.tar'
)
foreach ($name in $requiredFiles) {
    $path = Join-Path $PackageDir $name
    if (!(Test-Path $path)) { throw "Missing package file: $name" }
}

$bootstrapPath = Join-Path $PackageDir 'pjarczak_wsl_run_host.sh'
Convert-FileToLf $bootstrapPath

$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
if (!(Test-Path $wsl)) { throw 'wsl.exe not found' }

$distroList = & $wsl -l -q 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Failed to query installed WSL distros' }
if (-not ($distroList | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $DistroName })) {
    throw "WSL distro '$DistroName' is not installed"
}

$packageDirWsl = To-WslPath $PackageDir
$pluginCacheDirWsl = ''
if (-not [string]::IsNullOrWhiteSpace($PluginCacheDir)) {
    $pluginCacheDirWsl = To-WslPath $PluginCacheDir
}
$bootstrapWsl = "$packageDirWsl/pjarczak_wsl_run_host.sh"

if ($SkipProbe) {
    Write-Host 'WSL runtime core OK'
    exit 0
}

$probe = & $wsl -d $DistroName --user root -- sh $bootstrapWsl --probe $packageDirWsl $pluginCacheDirWsl 2>&1
if ($LASTEXITCODE -ne 0) {
    $probeText = ($probe | Out-String).Trim()
    if ($AllowMissingLinuxPlugin -and $probeText -match 'plugin_not_downloaded') {
        Write-Host 'WSL runtime package OK, linux plugin not downloaded yet.'
        Write-Host $probeText
        exit 0
    }
    throw "WSL runtime probe failed: $probeText"
}

Write-Host 'WSL runtime probe OK'
Write-Host (($probe | Out-String).Trim())
