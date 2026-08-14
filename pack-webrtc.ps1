# Assembles vcpkg-shaped webrtc archives from a built FrayxRulez/webrtc-uwp checkout.
# Belongs in UnigramDev/deps. One header archive shared by every configuration, plus one archive
# per configuration and architecture, so a build downloads only the lib it links.
param(
    [Parameter(Mandatory = $true)][string]$WebRtcSrc,   # C:\webrtc\src
    [Parameter(Mandatory = $true)][string]$Version,     # e.g. 2026-08-11
    [Parameter(Mandatory = $true)][string]$OutDir,
    [switch]$HeadersOnly
)
$ErrorActionPreference = 'Stop'
$WebRtcSrc = (Resolve-Path $WebRtcSrc).Path.TrimEnd('\')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

# third_party is 18,167 of the 22,137 headers and 163 of the 192 MB, and almost none of it is
# reachable from what Unigram compiles. These are the directories that are: either included
# directly by tgcalls, or by a webrtc header in a module tgcalls uses. Paths are preserved,
# because the includes are written as "third_party/libyuv/include/libyuv.h" and resolved through
# the checkout root. If a build ever fails on a missing header, add its directory here.
$thirdParty = @('abseil-cpp', 'libyuv', 'opus', 'libsrtp', 'openh264', 'ffmpeg', 'protobuf', 'perfetto', 'boringssl')

function New-Archive([string]$Staging, [string]$Name) {
    $out = Join-Path $OutDir $Name
    if (Test-Path $out) { Remove-Item $out }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($Staging, $out, 'Optimal', $false)
    Remove-Item $Staging -Recurse -Force
    "{0,-44} {1,7:N1} MB  SHA512 {2}" -f $Name, ((Get-Item $out).Length / 1MB), (Get-FileHash $out -Algorithm SHA512).Hash.ToLower()
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("webrtc-h-" + [System.Guid]::NewGuid().ToString('N'))
$inc = Join-Path $staging 'include'
$script:copied = 0

function Copy-Headers([string]$Root, [string]$Prefix) {
    Get-ChildItem $Root -Recurse -Include *.h,*.hpp,*.inc -File -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length).TrimStart('\')
        if ($Prefix) { $rel = Join-Path $Prefix $rel }
        $dst = Join-Path $inc $rel
        if (-not (Test-Path $dst)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
            Copy-Item $_.FullName $dst
            $script:copied++
        }
    }
}

# 1. The checkout root, minus third_party and build output. Keeps rtc_base/third_party/* (base64,
#    sigslot), which tgcalls includes directly and which lives inside the core tree.
Get-ChildItem $WebRtcSrc -Directory |
    Where-Object { $_.Name -notin @('third_party', 'out') } |
    ForEach-Object { Copy-Headers $_.FullName $_.Name }

# 2. The reachable third_party directories, at their original paths.
foreach ($d in $thirdParty) {
    $p = Join-Path $WebRtcSrc "third_party\$d"
    if (Test-Path $p) { Copy-Headers $p "third_party\$d" }
    else { Write-Warning "third_party\$d not present" }
}

# 3. abseil is also passed as an include root, so <absl/...> has to resolve; flatten it.
#    libyuv deliberately is NOT flattened: the standalone libyuv port owns include/libyuv.h, and
#    adding a second copy both conflicts in vcpkg and would silently decide which one every
#    project compiles against. tgcalls includes it as third_party/libyuv/include/libyuv.h, which
#    step 2 already provides.
Copy-Headers (Join-Path $WebRtcSrc 'third_party\abseil-cpp') $null

Set-Content -Path (Join-Path $staging 'REVISION') -Value (git -C $WebRtcSrc rev-parse HEAD)
"headers: {0:N0} files" -f $script:copied
New-Archive $staging "webrtc-$Version-headers.zip"

if ($HeadersOnly) { return }

foreach ($cfg in @('Release', 'Debug')) {
    foreach ($arch in @('x64', 'arm64')) {
        $lib = Join-Path $WebRtcSrc "out\msvc\uwp\$cfg\$arch\obj\webrtc.lib"
        if (-not (Test-Path $lib)) { Write-Warning "missing $lib"; continue }
        $s = Join-Path ([System.IO.Path]::GetTempPath()) ("webrtc-l-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $s 'lib') | Out-Null
        Copy-Item $lib (Join-Path $s 'lib\webrtc.lib')
        New-Archive $s ("webrtc-$Version-$arch-uwp-" + $cfg.ToLower() + ".zip")
    }
}
