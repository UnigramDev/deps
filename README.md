# Unigram prebuilt dependencies

WebRTC is impractical to build as part of a normal Unigram checkout: it needs depot_tools, a
~1.5 hour sync and ~20 GB of disk, for a multi-hour build, and it changes a few times a year at
most. This repository holds everything needed to produce it — the source-build script, the
packaging script, and the patches it needs — and its releases hold the resulting archives. Unigram
consumes those through a vcpkg overlay port in `Libraries/vcpkg-ports`, so a contributor never runs
any of this: the archives are downloaded on demand for the architecture being built, verified by
SHA512 and cached.

```
webrtc/    build.ps1  pack.ps1  patches/
```

The `libvlc-*` releases are left in place for the Unigram versions that shipped them; Unigram no
longer uses libvlc, and the scripts that built them are in this repository's history.

## Releases

Tags are `<name>-<upstream version>-<n>`, where `n` increments on any repackage that does not
change the upstream version. That maps onto vcpkg's `version` and `port-version`.

```
webrtc-2026-08-11-1  webrtc-2026-08-11-headers.zip            18 MB   (shared by all configurations)
                     webrtc-2026-08-11-x64-uwp-release.zip    85 MB
                     webrtc-2026-08-11-x64-uwp-debug.zip     135 MB
                     webrtc-2026-08-11-arm64-uwp-release.zip  80 MB
                     webrtc-2026-08-11-arm64-uwp-debug.zip   129 MB
```

Headers and libraries are separate archives for webrtc so that a build downloads only the
configuration it links, rather than all of them. From 2026-10-26 a release also carries the four
libraries as `-windows-`, built for desktop, which the vcpkg `-windows` triplets link.

**Every release description must name the exact source commit it was built from**, and the fork
must be pushed first. A release whose source is a local working tree cannot be reproduced.

## webrtc

Source: [UnigramDev/webrtc-uwp](https://github.com/UnigramDev/webrtc-uwp), branch `m123`.

The fork covers `src` only. `build/`, `third_party/` and two of its sub-repositories are managed
by gclient and cannot be forked conveniently, so their changes live in `webrtc/patches/` — six
patches.

1. Fetch, patch and build — one script does all three. The fork commit is **pinned by SHA** at the
   top of it; update it when the fork moves.
   ```powershell
   .\webrtc\build.ps1                                    # everything, into C:\webrtc
   .\webrtc\build.ps1 -Root D:\webrtc                    # somewhere with room
   .\webrtc\build.ps1 -Target uwp -Arch x64 -Configuration Release   # one drop
   .\webrtc\build.ps1 -SkipAcquire                       # rebuild an existing checkout
   ```
   `-Target` is `uwp` (`target_os="winuwp"`), `windows` (`target_os="win"`), or both by default.
   Both link the dynamic CRT, which for desktop takes `patches/build/dynamic_crt.patch`: its
   default is the static one, and the code webrtc.lib is linked into is built `/MD`.

   Every step is re-runnable: an existing depot_tools or checkout is reused, and an
   already-applied patch is detected and skipped rather than failing.

   It builds with **Visual Studio 2022 or 18**, whichever vswhere reports as newest. Both produce
   a clean build; 18 is passed through `vs2022_install`, which webrtc's toolchain detection honours
   even though it does not know the year.
2. Push the fork.
3. Package everything at once:
   ```powershell
   .\webrtc\pack.ps1 -WebRtcSrc C:\webrtc\src -Version 2026-08-11 -OutDir .\artifacts
   ```
4. Create the release, attach the nine archives, and record the commit.
5. Update the SHA512s in Unigram's `Libraries/vcpkg-ports/webrtc/portfile.cmake`.

The header archive carries only the checkout root plus the `third_party` directories that
Unigram's compilation actually reaches — 7,600 files instead of 22,100, 18 MB instead of 192 MB.
The list is at the top of `pack.ps1`. If a build ever fails on a missing header, add its
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
