# Fetches, patches and builds WebRTC for UWP from the UnigramDev/webrtc-uwp fork.
#
#   .\build.ps1                                   # everything, into C:\webrtc
#   .\build.ps1 -Arch x64 -Configuration Release  # one drop
#   .\build.ps1 -SkipAcquire                      # rebuild an existing checkout
#
# The fork covers src only. build/, third_party/ and two of its sub-repositories are managed by
# gclient and cannot be forked conveniently, so their changes live in patches/ and are applied
# here. Every step is re-runnable: an existing checkout is reused and an already-applied patch is
# detected rather than failing.
param(
    [string]$Root = 'C:\webrtc',
    [ValidateSet('x64', 'arm64')][string[]]$Arch = @('x64', 'arm64'),
    [ValidateSet('Release', 'Debug')][string[]]$Configuration = @('Release', 'Debug'),
    [switch]$SkipAcquire
)
$ErrorActionPreference = 'Stop'

# Pinned exactly: the upstream release branch, and the fork commit built into the published
# binaries. A branch name here would silently drift from what was shipped.
$UpstreamBranch = 'branch-heads/6312'
$ForkUrl        = 'https://github.com/UnigramDev/webrtc-uwp.git'
$ForkCommit     = '801b01361857fd9afd40f0efd29034b0e48001c7'

$PatchDir    = Join-Path $PSScriptRoot 'patches'
$DepotTools  = Join-Path $Root 'depot_tools'
$Src         = Join-Path $Root 'src'

function Invoke-Checked([string]$What, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}

# Applies a patch to a gclient-managed repository. --check --reverse succeeds when the patch is
# already in the tree, which is what makes a second run a no-op instead of an error.
function Use-Patch([string]$Repo, [string]$Patch) {
    if (-not (Test-Path $Repo)) { throw "missing repository: $Repo" }
    Push-Location $Repo
    try {
        & git apply --check --reverse --ignore-whitespace $Patch 2>$null
        if ($LASTEXITCODE -eq 0) {
            "  already applied: $(Split-Path $Patch -Leaf)"
            return
        }
        "  applying: $(Split-Path $Patch -Leaf) -> $Repo"
        & git apply --3way --ignore-whitespace $Patch
        if ($LASTEXITCODE -ne 0) { throw "failed to apply $Patch" }
    } finally { Pop-Location }
}

# Visual Studio 2022 or 18, whichever is newest; both build it. vswhere rather than a hardcoded
# path, so Professional and Enterprise installs work too.
function Get-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw "vswhere not found at $vswhere" }
    $path = & $vswhere -version '[17.0,19.0)' -latest -products * -property installationPath
    if (-not $path) { throw 'Visual Studio 2022 or newer is required to build WebRTC, and was not found.' }
    return $path
}

"Root:        $Root"
"Fork commit: $ForkCommit"

if (-not $SkipAcquire) {
    if (-not (Test-Path (Join-Path $DepotTools 'gclient.bat'))) {
        "`nDownloading depot_tools..."
        New-Item -ItemType Directory -Force -Path $DepotTools | Out-Null
        $zip = Join-Path $Root 'depot_tools.zip'
        Invoke-WebRequest -Uri 'https://storage.googleapis.com/chrome-infra/depot_tools.zip' -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $DepotTools -Force
        Remove-Item $zip
    } else {
        'depot_tools already present.'
    }
}

$env:PATH = "$DepotTools;$env:PATH"
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:GYP_MSVS_VERSION = '2022'

if (-not $SkipAcquire) {
    if (-not (Test-Path $Src)) {
        "`nFetching the WebRTC code base, this takes a while..."
        Push-Location $Root
        try {
            Invoke-Checked 'gclient' { & gclient }
            Invoke-Checked 'fetch'   { & fetch --nohooks webrtc }
        } finally { Pop-Location }
    } else {
        'src already present, skipping fetch.'
    }

    Push-Location $Src
    try {
        "`nSyncing dependencies to $UpstreamBranch..."
        Invoke-Checked 'git checkout' { & git checkout $UpstreamBranch }
        Invoke-Checked 'gclient sync' { & gclient sync -D -r $UpstreamBranch }

        "`nChecking out the fork at $ForkCommit..."
        & git remote get-url upstream *>$null
        if ($LASTEXITCODE -ne 0) { Invoke-Checked 'git remote add' { & git remote add upstream $ForkUrl } }
        Invoke-Checked 'git fetch'    { & git fetch upstream }
        Invoke-Checked 'git checkout' { & git checkout $ForkCommit }
    } finally { Pop-Location }

    "`nApplying patches..."
    Use-Patch (Join-Path $Src 'build')                     (Join-Path $PatchDir 'build\fix.patch')

    # PROCESSOR_ARCHITECTURE rather than wmic, which is deprecated and already absent from some
    # Windows 11 installs -- there it returned nothing and this patch was skipped in silence.
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        Use-Patch (Join-Path $Src 'build')                 (Join-Path $PatchDir 'build\woa_support.patch')
    }

    Use-Patch (Join-Path $Src 'third_party')               (Join-Path $PatchDir 'third_party\fix.patch')
    Use-Patch (Join-Path $Src 'third_party\boringssl\src') (Join-Path $PatchDir 'third_party\string.patch')
    Use-Patch (Join-Path $Src 'third_party\libyuv')        (Join-Path $PatchDir 'third_party\libyuv\fix.patch')
}

$vs = Get-VisualStudio
"`nUsing $vs"

# build/vs_toolchain.py maps only the years 2019 and 2022, but vs<year>_install short-circuits both
# the version detection and the path lookup, so pointing it at an 18 install is enough and
# GYP_MSVS_VERSION stays at 2022. It also runs vcvarsall itself after clearing
# VSINSTALLDIR/INCLUDE/LIB, so a developer environment imported here would be discarded.
$env:vs2022_install = $vs

Push-Location $Src
try {
    foreach ($a in $Arch) {
        foreach ($c in $Configuration) {
            $isDebug = if ($c -eq 'Release') { 'false' } else { 'true' }
            $out = "out\msvc\uwp\$c\$a"

            "`nConfiguring $a $c..."
            $gnArgs = "is_debug=$isDebug use_lld=false is_clang=false rtc_include_tests=false " +
                      "rtc_build_tools=false rtc_win_video_capture_winrt=true target_os=\`"winuwp\`" " +
                      "rtc_build_examples=false rtc_win_use_mf_h264=true rtc_enable_protobuf=false " +
                      "rtc_disable_metrics=true rtc_include_dav1d_in_internal_decoder_factory=false " +
                      "treat_warnings_as_errors=false use_custom_libcxx=false fatal_linker_warnings=false " +
                      "target_cpu=\`"$a\`""
            Invoke-Checked "gn gen $a $c" { & gn gen --ide=vs2022 $out --filters=//:webrtc "--args=$gnArgs" }

            "`nBuilding $a $c..."
            Invoke-Checked "ninja $a $c" { & ninja -C $out }

            $lib = Join-Path $Src "$out\obj\webrtc.lib"
            "  {0} -> {1:N0} MB" -f $lib, ((Get-Item $lib).Length / 1MB)
        }
    }
} finally { Pop-Location }

"`nDone. Package with:  .\pack.ps1 -WebRtcSrc $Src -Version <date> -OutDir .\artifacts"
