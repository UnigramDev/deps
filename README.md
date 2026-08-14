# Unigram prebuilt dependencies

Two of Unigram's native dependencies are impractical to build as part of a normal checkout:

| | why it is not built from source |
|---|---|
| **libvlc** | needs Docker and the VideoLAN contrib toolchain; an 8.8 GB submodule |
| **webrtc** | needs depot_tools, a ~1.5 hour sync and ~20 GB of disk, for a multi-hour build |

Both change a few times a year at most. This repository holds everything needed to produce them —
the source-build scripts, the patches, and the packaging scripts — and its releases hold the
resulting archives. Unigram consumes those through vcpkg overlay ports in
`Libraries/vcpkg-ports`, so a contributor never runs any of this: the archives are downloaded on
demand for the architecture being built, verified by SHA512 and cached.

```
libvlc/    build.ps1  plugins-cache.ps1  pack-libvlc.ps1  patches/  VideoLAN.LibVLC.UWP.nuspec
webrtc/    build-webrtc.ps1  pack-webrtc.ps1  patches/
```

## Releases

Tags are `<name>-<upstream version>-<n>`, where `n` increments on any repackage that does not
change the upstream version. That maps onto vcpkg's `version` and `port-version`.

```
libvlc-3.0.23-1      libvlc-3.0.23-x64-uwp.zip                14 MB
                     libvlc-3.0.23-arm64-uwp.zip              12 MB

webrtc-2026-08-11-1  webrtc-2026-08-11-headers.zip            18 MB   (shared by all configurations)
                     webrtc-2026-08-11-x64-uwp-release.zip    85 MB
                     webrtc-2026-08-11-x64-uwp-debug.zip     135 MB
                     webrtc-2026-08-11-arm64-uwp-release.zip  80 MB
                     webrtc-2026-08-11-arm64-uwp-debug.zip   129 MB
```

Headers and libraries are separate archives for webrtc so that a build downloads only the
configuration it links, rather than all four.

**Every release description must name the exact source commit it was built from**, and the fork
must be pushed first. For libvlc this is a licence obligation, not a convention: LGPL-2.1 requires
the corresponding source to be available to anyone who receives the binary. A release whose source
is a local working tree does not satisfy it.

## libvlc

Source: [UnigramDev/vlc](https://github.com/UnigramDev/vlc), branch `unigram-12.7.5`.

1. Build the fork. `build.ps1` runs the VideoLAN Docker image and applies `patches/` to the
   submodule; it currently expects to run from the Unigram checkout's `Libraries/vlc`.
   ```powershell
   .\build.ps1 -arch x64,ARM64
   ```
2. Push the fork, with **no uncommitted changes** in its working tree.
3. Package each architecture:
   ```powershell
   .\libvlc\pack-libvlc.ps1 -VlcDir <unigram>\Libraries\vlc -Arch x64   -Version 3.0.23 -OutFile libvlc-3.0.23-x64-uwp.zip
   .\libvlc\pack-libvlc.ps1 -VlcDir <unigram>\Libraries\vlc -Arch arm64 -Version 3.0.23 -OutFile libvlc-3.0.23-arm64-uwp.zip
   ```
   The file list is read from `VideoLAN.LibVLC.UWP.nuspec`: the curated plugin set plus the
   generated `plugins.dat` cache. It is not duplicated in the script.
4. Create the release, attach both archives, and record the commit.
5. Update the SHA512s in Unigram's `Libraries/vcpkg-ports/libvlc/portfile.cmake`.

## webrtc

Source: [UnigramDev/webrtc-uwp](https://github.com/UnigramDev/webrtc-uwp), branch `m123`.

The fork covers `src` only. `build/`, `third_party/` and two of its sub-repositories are managed
by gclient and cannot be forked conveniently, so their changes live in `webrtc/patches/` — five
patches, 211 lines across 11 files.

1. Fetch, patch and build — one script does all three. The fork commit is **pinned by SHA** at the
   top of it; update it when the fork moves.
   ```powershell
   .\webrtc\build-webrtc.ps1                                    # everything, into C:\webrtc
   .\webrtc\build-webrtc.ps1 -Root D:\webrtc                    # somewhere with room
   .\webrtc\build-webrtc.ps1 -Arch x64 -Configuration Release   # one drop
   .\webrtc\build-webrtc.ps1 -SkipAcquire                       # rebuild an existing checkout
   ```
   Every step is re-runnable: an existing depot_tools or checkout is reused, and an
   already-applied patch is detected and skipped rather than failing.

   It builds with **Visual Studio 2022**, located through vswhere — that is the toolchain this has
   been built and shipped with, and it has never been built with 18. The resulting static library
   links cleanly into projects built with the newer v145 toolset.
2. Push the fork.
3. Package everything at once:
   ```powershell
   .\webrtc\pack-webrtc.ps1 -WebRtcSrc C:\webrtc\src -Version 2026-08-11 -OutDir .\artifacts
   ```
4. Create the release, attach the five archives, and record the commit.
5. Update the SHA512s in Unigram's `Libraries/vcpkg-ports/webrtc/portfile.cmake`.

The header archive carries only the checkout root plus the `third_party` directories that
Unigram's compilation actually reaches — 7,600 files instead of 22,100, 18 MB instead of 192 MB.
The list is at the top of `pack-webrtc.ps1`. If a build ever fails on a missing header, add its
directory there and repackage; the failure is a compile error naming the file, so it is
self-diagnosing.

It deliberately does **not** ship `include/libyuv.h`. That path belongs to the standalone `libyuv`
port, and a second copy would both conflict in vcpkg and silently decide which libyuv every
project compiles against. WebRTC's patched libyuv stays at `third_party/libyuv/include/libyuv.h`,
which is how tgcalls includes it.

## Verifying an archive

```powershell
(Get-FileHash <file> -Algorithm SHA512).Hash.ToLower()
```

must match the value in the corresponding portfile.
