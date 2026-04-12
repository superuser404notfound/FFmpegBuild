# FFmpegBuild

Minimal FFmpeg build for Apple platforms — only demuxing + decoding, zero network dependencies.

[![License: LGPL v3](https://img.shields.io/badge/License-LGPL%20v3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20tvOS%2016%2B%20%7C%20macOS%2014%2B-lightgrey)]()

## What's Included

| Library | Purpose | Size (per arch) |
|---|---|---|
| libavformat | Container demuxing (MKV, MP4, HLS, TS, AVI, FLV, OGG, ...) | ~2 MB |
| libavcodec | Video + audio decoding with VideoToolbox HW acceleration | ~6-8 MB |
| libavutil | Shared utilities | ~2 MB |
| libswresample | Audio resampling + format conversion | ~0.3 MB |

## What's NOT Included

- ❌ Network/TLS (no gnutls, no OpenSSL, no SecureTransport)
- ❌ Encoders (no video/audio encoding)
- ❌ Muxers (no container writing)
- ❌ Filters (no libavfilter)
- ❌ Scaling (no libswscale)
- ❌ Devices (no libavdevice)
- ❌ Programs (no ffmpeg/ffplay/ffprobe binaries)

## Why No Network?

Network I/O is handled by Apple's native `URLSession` / `Network.framework`, which provides:
- TLS 1.3 + HTTP/2 + HTTP/3 (future-proof, never deprecated)
- System proxy + VPN support
- App Transport Security compliance
- Zero external dependencies

FFmpeg receives data through a custom `avio_alloc_context` read callback — it never touches the network directly.

## Building

```bash
# Build for all platforms
./build.sh

# Build only tvOS
./build.sh tvos

# Clean
./build.sh clean
```

Requires: Xcode 26+, ~10-30 minutes build time.

## Integration

### As SPM Dependency

```swift
dependencies: [
    .package(path: "../FFmpegBuild")
]

// In your target:
.product(name: "FFmpegBuild", package: "FFmpegBuild")
```

## Supported Codecs

### Video Decoders
H.264, HEVC (+ VideoToolbox HW), VP8, VP9, AV1, MPEG-2, MPEG-4, VC-1

### Audio Decoders
AAC, AC3, EAC3, FLAC, MP3, Opus, Vorbis, TrueHD, DTS, ALAC, PCM

### Subtitle Decoders
SRT, ASS/SSA, WebVTT, PGS, DVB, DVD

### Container Demuxers
MKV/WebM, MP4/M4A, HLS, DASH, MPEG-TS, AVI, FLV, OGG, WAV, MP3

## License

LGPL 3.0 — same as FFmpeg itself. App Store compatible when dynamically linked.
