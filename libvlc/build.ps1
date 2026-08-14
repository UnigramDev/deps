# Builds libvlc for UWP from the UnigramDev/vlc fork, using the VideoLAN Docker image, and
# generates the plugin cache.
#
#   .\build.ps1                                  # both architectures, ..\..\vlc
#   .\build.ps1 -VlcSrc D:\vlc -Arch x64
#
# The fork carries its changes as commits, so there is nothing to patch here.
param(
    # The VLC checkout. Defaults to a sibling of this repository.
    [string]$VlcSrc = (Join-Path $PSScriptRoot '..\..\vlc'),
    [ValidateSet('x64', 'ARM64', IgnoreCase = $false)]
    [string[]]$Arch = @('x64', 'ARM64')
)
$ErrorActionPreference = 'Stop'

$VlcSrc = (Resolve-Path $VlcSrc).Path.TrimEnd('\')
if (-not (Test-Path (Join-Path $VlcSrc 'extras\package\win32\build.sh'))) {
    throw "$VlcSrc does not look like a VLC checkout"
}
Write-Host "==> VLC source: $VlcSrc"

$ArchMap = @{ 'x64' = 'x86_64'; 'arm64' = 'aarch64' }
$NormalizedArch = foreach ($a in $Arch) {
    $key = $a.ToLower()
    if ($ArchMap.ContainsKey($key)) { $ArchMap[$key] } else { throw "Unknown arch '$a'" }
}

# revision.txt is what the build stamps into src/revision.c.
$RevisionFile = Join-Path $PSScriptRoot 'revision.txt'
if (Test-Path $RevisionFile) {
    $DestFolder = Join-Path $VlcSrc 'src'
    # Normalise rather than copy: the Makefile inside the container cats this file straight into
    # a C string literal, so a CRLF here puts a bare CR inside the literal and src/revision.c
    # fails to compile ("expected expression").
    $Revision = (Get-Content $RevisionFile -Raw).Trim()
    [System.IO.File]::WriteAllText((Join-Path $DestFolder 'revision.txt'), $Revision + "`n")
    Write-Host "Copied revision.txt to $DestFolder ($Revision)"
} else {
    Write-Host 'revision.txt not found, skipping...'
}

$Mounted = '"' + ($VlcSrc -replace '\\', '/') + '"'
$DockerCommand = "cd ../vlc`n"
foreach ($a in $NormalizedArch) {
    # -D takes its value as a separate argument. Passing it as -D=<path> makes getopts capture
    # the '=' as part of OPTARG, which ends up in the -fdebug-prefix-map replacement and puts a
    # literal '=' in front of every source path recorded in the PDBs.
    $DockerCommand += "extras/package/win32/build.sh -a $a -z -r -u -w -D $Mounted`n"
}
$DockerCommand += "exit`n"

Write-Host 'Launching Docker...'

# No -it: it needs a terminal on stdin, so the script cannot run from CI or any non-interactive
# shell ("cannot attach stdin to a TTY-enabled container").
docker run --rm -v "${VlcSrc}:/vlc" registry.videolan.org/vlc-debian-llvm-uwp:20211020111246 bash -c "$DockerCommand"

if ($LASTEXITCODE -ne 0) {
    # Without this the script used to carry on and package whatever happened to be lying around
    # from an earlier build, turning a failed build into a stale package.
    throw "Docker build failed with exit code $LASTEXITCODE"
}

# Cross-compiled builds skip the cache (Makefile.am only runs vlc-cache-gen when build == host),
# so without this libvlc rescans every plugin on each startup.
Write-Host 'Generating plugin cache...'
& (Join-Path $PSScriptRoot 'plugins-cache.ps1') -VlcSrc $VlcSrc

$VlcVersion = (Get-ChildItem -Path (Join-Path $VlcSrc 'win64-uwp') -Directory -Filter 'vlc-*' |
    Select-Object -First 1).Name -replace '^vlc-', ''
if (-not $VlcVersion) { throw "Could not determine the built VLC version from $VlcSrc\win64-uwp" }

Write-Host ""
Write-Host "Built VLC $VlcVersion. Package with:"
foreach ($a in $Arch) {
    $lower = $a.ToLower()
    Write-Host "  .\pack.ps1 -VlcSrc $VlcSrc -Arch $lower -Version $VlcVersion -OutFile libvlc-$VlcVersion-$lower-uwp.zip"
}
