# Unigram prebuilt dependencies

Two of Unigram's native dependencies are impractical to build as part of a normal checkout:

| | why it is not built from source |
|---|---|
| **libvlc** | needs Docker and the VideoLAN contrib toolchain; an 8.8 GB submodule |
| **webrtc** | needs depot_tools, a ~1.5 hour sync and ~20 GB of disk, for a multi-hour build |

Both change a few times a year at most. This repository holds the scripts that package them and,
in its releases, the archives themselves. Unigram consumes those through vcpkg overlay ports in
`Libraries/vcpkg-ports`, so a contributor never runs any of this — the archives are downloaded on
demand for the architecture being built, verified by SHA512 and cached.

## Releases

Tags are `<name>-<upstream version>-<n>`, where `n` increments on any repackage that does not
change the upstream version. That maps onto vcpkg's `version` and `port-version`.

```
libvlc-3.0.23-1     libvlc-3.0.23-x64-uwp.zip              ~14 MB
                    libvlc-3.0.23-arm64-uwp.zip            ~12 MB

webrtc-2026-08-11-1 webrtc-2026-08-11-headers.zip          ~18 MB   (shared by all configurations)
                    webrtc-2026-08-11-x64-uwp-release.zip  ~86 MB
                    webrtc-2026-08-11-x64-uwp-debug.zip    ~136 MB
                    webrtc-2026-08-11-arm64-uwp-release.zip  ~80 MB
                    webrtc-2026-08-11-arm64-uwp-debug.zip    ~129 MB
```

Headers and libraries are separate archives for webrtc so that a build downloads only the
configuration it links, rather than all four.

**Every release description must name the exact source commit it was built from**, and the fork
must be pushed first. For libvlc this is a licence obligation, not a convention: LGPL-2.1 requires
the corresponding source to be available to anyone who receives the binary. A release whose source
is a local working tree does not satisfy it.

## Publishing

### libvlc

1. Build the fork — `Libraries/vlc/build.ps1 -arch x64,ARM64` in the Unigram checkout, which uses
   Docker and applies the fork's patches.
2. Push `UnigramDev/vlc` so the built commit is public, with **no uncommitted changes** in the
   working tree.
3. Package each architecture:
   ```powershell
   .\pack-libvlc.ps1 -VlcDir <unigram>\Libraries\vlc -Arch x64   -Version 3.0.23 -OutFile libvlc-3.0.23-x64-uwp.zip
   .\pack-libvlc.ps1 -VlcDir <unigram>\Libraries\vlc -Arch arm64 -Version 3.0.23 -OutFile libvlc-3.0.23-arm64-uwp.zip
   ```
   The file list is read from `VideoLAN.LibVLC.UWP.nuspec`: the curated plugin set plus the
   generated `plugins.dat` cache. It is not duplicated here.
4. Create the release, attach both archives, and record the commit.
5. Update the SHA512s in `Libraries/vcpkg-ports/libvlc/portfile.cmake`.

### webrtc

1. Build the fork — `Libraries/webrtc/build.cmd` for each architecture and configuration.
2. Push `FrayxRulez/webrtc-uwp`.
3. Package everything at once:
   ```powershell
   .\pack-webrtc.ps1 -WebRtcSrc C:\webrtc\src -Version 2026-08-11 -OutDir .\artifacts
   ```
4. Create the release, attach the five archives, and record the commit.
5. Update the SHA512s in `Libraries/vcpkg-ports/webrtc/portfile.cmake`.

The header archive carries only the checkout root plus the `third_party` directories that
Unigram's compilation actually reaches — 7,600 files instead of 22,100, 18 MB instead of 192 MB.
The list is at the top of `pack-webrtc.ps1`. If a build ever fails on a missing header, add its
directory there and repackage; the failure is a compile error naming the file, so it is
self-diagnosing.

## Verifying an archive

```powershell
(Get-FileHash <file> -Algorithm SHA512).Hash.ToLower()
```

must match the value in the corresponding portfile.
