<h1 align="center">FFmpegBuild</h1>

<p align="center">
  <b>Slim FFmpeg xcframeworks for Apple platforms.</b><br>
  Demuxing and decoding only. No network stack, no encoders, no CLI binaries.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/FFmpeg-7.1-brightgreen">
  <img src="https://img.shields.io/badge/dav1d-1.5.1-blue">
  <img src="https://img.shields.io/badge/iOS-16%2B-black?logo=apple">
  <img src="https://img.shields.io/badge/tvOS-16%2B-black?logo=apple">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img src="https://img.shields.io/badge/license-LGPL--3.0-lightgrey">
</p>

---

## Why

Full FFmpeg builds for iOS land at 40-70 MB because they bundle a TLS stack, encoders, filters, and a dozen protocols your app will never use. For a player, most of that is dead weight. Apple already ships HTTP/3, `URLSession`, `Network.framework`, VideoToolbox and AVFoundation. So this build strips out everything you don't need and keeps what you do.

**~10 MB per architecture, zero network dependencies, one build script.**

## In

| Library        | What it does                                          |
| -------------- | ----------------------------------------------------- |
| libavformat    | Demux MKV, MP4, HLS, DASH, MPEG-TS, AVI, WebM, OGG, … |
| libavcodec     | Decode video + audio (with VideoToolbox bridge)       |
| libavutil      | Shared primitives                                     |
| libswresample  | Audio resampling / channel remap / format convert    |
| **dav1d**      | Fast AV1 software decoder (separate xcframework)      |

## Out

Anything the app layer should already handle or doesn't need:

- Network / TLS: FFmpeg reads from an `avio_alloc_context` callback, you wire `URLSession` to it
- Encoders and muxers
- libavfilter, libswscale, libavdevice
- Programs (`ffmpeg`, `ffplay`, `ffprobe`)
- Hardware accel layers other than VideoToolbox
- Text subtitle rendering (do that in SwiftUI)

## Build

```sh
./build.sh          # all platforms
./build.sh tvos     # single platform
./build.sh clean    # wipe everything
```

Needs Xcode 16+ and roughly 10-30 minutes depending on your machine. Both FFmpeg and dav1d sources clone on first run.

Output lands in `Sources/` as xcframeworks, ready to consume via Swift Package Manager.

## Use

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/superuser404notfound/FFmpegBuild", branch: "main")
]

// Target:
.product(name: "FFmpegBuild", package: "FFmpegBuild")
```

Then import the modules you need: `Libavformat`, `Libavcodec`, `Libavutil`, `Libswresample`, `Libdav1d`.

## Decoder support

- **Video (hardware via VideoToolbox)**: H.264, HEVC up to Main10 (HDR10/DV Profile 8)
- **Video (software)**: AV1 (dav1d), VP9, VP8, MPEG-2, MPEG-4, VC-1
- **Audio**: AAC, AC3, EAC3 (incl. JOC detection for Atmos), FLAC, MP3, Opus, Vorbis, TrueHD, DTS, ALAC, PCM
- **Subtitles**: SRT, ASS, SSA, WebVTT, PGS, DVB, DVD

HDR metadata (BT.2020, SMPTE ST 2084 / PQ, HLG, DV RPU) is preserved end-to-end so the decode pipeline can tag frames correctly.

## Size

Per architecture, release configuration:

| Target                | FFmpeg    | dav1d    | Total   |
| --------------------- | --------- | -------- | ------- |
| iOS / tvOS arm64      | ~10.5 MB  | ~1.2 MB  | ~12 MB  |
| macOS arm64           | ~10.5 MB  | ~1.2 MB  | ~12 MB  |
| macOS x86_64          | ~11 MB    | ~1.3 MB  | ~12 MB  |

Assembly-optimized paths are enabled where the Apple toolchain permits.

## Built with

This package is vibe-coded, assembled and maintained by [Vincent Herbst](https://github.com/superuser404notfound) in close pair-programming with **Claude** (Anthropic). The commit log is the receipt: nearly every commit carries a `Co-Authored-By: Claude` trailer.

## License

[LGPL-3.0](LICENSE), same as upstream FFmpeg. App Store compatible when linked dynamically.

---

<p align="center"><sub>Used by <a href="https://github.com/superuser404notfound/AetherEngine">AetherEngine</a>.</sub></p>
