# Assembles a vcpkg-shaped libvlc archive from a built VLC tree.
#
# The file list is not written out again here: it is read from the existing
# VideoLAN.LibVLC.UWP.nuspec, which is already the curated set of plugins Unigram needs plus
# the generated plugin cache. Belongs in UnigramDev/deps alongside the fork's build script.
param(
    [Parameter(Mandatory = $true)][string]$VlcDir,      # the Libraries\vlc folder holding the nuspec
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Arch,
    [Parameter(Mandatory = $true)][string]$Version,     # e.g. 3.0.23
    [Parameter(Mandatory = $true)][string]$OutFile
)
$ErrorActionPreference = 'Stop'

$nuspec = Join-Path $VlcDir 'VideoLAN.LibVLC.UWP.nuspec'
$prefix = "build/win10-$Arch/"
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("libvlc-" + [System.Guid]::NewGuid().ToString('N'))

# src="..." target="..." pairs, restricted to this architecture.
$pairs = [regex]::Matches(
    (Get-Content $nuspec -Raw),
    '<file\s+src="(?<src>[^"]+)"\s+target="(?<target>[^"]+)"\s*/>') |
    ForEach-Object { [pscustomobject]@{
        Src    = $_.Groups['src'].Value.Replace('$vlcver$', $Version)
        Target = $_.Groups['target'].Value.Replace('$vlcver$', $Version) } } |
    Where-Object { $_.Target.StartsWith($prefix) }

if (-not $pairs) { throw "No entries for $Arch in $nuspec" }

function Convert-Path2([string]$target) {
    # nuspec layout -> vcpkg layout
    $rel = $target.Substring($prefix.Length)
    switch -regex ($rel) {
        '^sdk/include/(.*)$' { return "include/$($Matches[1])" }
        '^sdk/lib/(.*)$'     { return "lib/$($Matches[1])" }
        '^plugins/(.*)$'     { return "share/libvlc/plugins/$($Matches[1])" }
        '^[^/]+\.dll$'       { return "bin/$rel" }
        default              { throw "Unhandled entry: $rel" }
    }
}

foreach ($p in $pairs) {
    $src = Join-Path $VlcDir $p.Src
    if (-not (Test-Path $src)) { throw "Missing: $src" }
    $dst = Join-Path $staging (Convert-Path2 $p.Target).Replace('/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $src $dst
}

# LGPL obliges shipping the license with the binaries; vcpkg also expects one.
$copying = Join-Path $VlcDir "vlc\COPYING.LIB"
if (Test-Path $copying) { Copy-Item $copying (Join-Path $staging 'copyright') }

if (Test-Path $OutFile) { Remove-Item $OutFile }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $OutFile, 'Optimal', $false)
Remove-Item $staging -Recurse -Force

$sha = (Get-FileHash $OutFile -Algorithm SHA512).Hash.ToLower()
"{0}  {1:N1} MB  {2} files" -f (Split-Path $OutFile -Leaf), ((Get-Item $OutFile).Length / 1MB), $pairs.Count
"SHA512 $sha"
