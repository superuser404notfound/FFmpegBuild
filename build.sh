#!/bin/zsh
#
# FFmpegBuild — Minimal FFmpeg cross-compilation for Apple platforms.
#
# Usage:
#   ./build.sh          # Build all platforms
#   ./build.sh clean    # Remove all build artifacts
#
set -e

FFMPEG_VERSION="n7.1"
FFMPEG_REPO="https://github.com/FFmpeg/FFmpeg.git"
SCRIPT_DIR="${0:a:h}"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/Sources"
FFMPEG_SRC="${BUILD_DIR}/ffmpeg-src"

# ─────────────────────────────────────────────────────────

fetch_ffmpeg() {
    if [[ -d "${FFMPEG_SRC}" ]]; then
        echo "→ FFmpeg source already exists, skipping clone"
        return
    fi
    echo "→ Cloning FFmpeg ${FFMPEG_VERSION}..."
    git clone --depth 1 --branch "${FFMPEG_VERSION}" "${FFMPEG_REPO}" "${FFMPEG_SRC}"
}

COMMON_FLAGS=(
    --enable-static --disable-shared --enable-pic
    --enable-optimizations --enable-stripping --disable-debug
    --disable-autodetect --disable-doc --disable-programs
    --disable-devices --disable-outdevs --disable-indevs
    --disable-postproc --disable-avdevice --disable-avfilter
    --disable-swscale --disable-encoders --disable-muxers
    --disable-bsfs --disable-network --disable-protocols
    --disable-d3d11va --disable-dxva2 --disable-vaapi --disable-vdpau
    --disable-gray --disable-iconv --disable-bzlib
    --disable-linux-perf --disable-symver --disable-swscale-alpha
    --enable-avcodec --enable-avformat --enable-avutil --enable-swresample
    --enable-videotoolbox --enable-audiotoolbox
    --enable-protocol=file --enable-protocol=pipe --enable-protocol=data
    --disable-demuxers
    --enable-demuxer=hls --enable-demuxer=dash --enable-demuxer=matroska
    --enable-demuxer=mov --enable-demuxer=mpegts --enable-demuxer=mpegps
    --enable-demuxer=avi --enable-demuxer=flv --enable-demuxer=h264
    --enable-demuxer=hevc --enable-demuxer=aac --enable-demuxer=ac3
    --enable-demuxer=eac3 --enable-demuxer=flac --enable-demuxer=ogg
    --enable-demuxer=wav --enable-demuxer=mp3 --enable-demuxer=srt
    --enable-demuxer=ass --enable-demuxer=concat --enable-demuxer=data
    --disable-decoders
    --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=vp8
    --enable-decoder=vp9 --enable-decoder=av1 --enable-decoder=mpeg2video
    --enable-decoder=mpeg4 --enable-decoder=vc1
    --enable-decoder=aac --enable-decoder=aac_latm --enable-decoder=ac3
    --enable-decoder=eac3 --enable-decoder=flac --enable-decoder=mp3
    --enable-decoder=mp3float --enable-decoder=opus --enable-decoder=vorbis
    --enable-decoder=truehd --enable-decoder=dca --enable-decoder=alac
    --enable-decoder=pcm_s16le --enable-decoder=pcm_s24le --enable-decoder=pcm_f32le
    --enable-decoder=ass --enable-decoder=srt --enable-decoder=subrip
    --enable-decoder=movtext --enable-decoder=dvdsub --enable-decoder=dvbsub
    --enable-decoder=pgssub --enable-decoder=webvtt
    --disable-parsers
    --enable-parser=aac --enable-parser=aac_latm --enable-parser=ac3
    --enable-parser=flac --enable-parser=h264 --enable-parser=hevc
    --enable-parser=mpegaudio --enable-parser=mpeg4video
    --enable-parser=mpegvideo --enable-parser=opus --enable-parser=vorbis
    --enable-parser=vp8 --enable-parser=vp9 --enable-parser=av1
    --enable-bsf=aac_adtstoasc --enable-bsf=h264_mp4toannexb
    --enable-bsf=hevc_mp4toannexb --enable-bsf=extract_extradata
)

build_one() {
    local KEY="$1" SDK="$2" ARCH="$3" TARGET="$4" MIN_VER="$5"

    echo ""
    echo "━━━ Building: ${KEY} (${ARCH} for ${SDK}) ━━━"

    local SDK_PATH=$(xcrun --sdk "${SDK}" --show-sdk-path)
    local INSTALL_DIR="${BUILD_DIR}/thin/${KEY}"
    mkdir -p "${INSTALL_DIR}"

    local CFLAGS="-arch ${ARCH} -isysroot ${SDK_PATH} -target ${TARGET} -fno-common -DHAVE_FORK=0"
    local LDFLAGS="-arch ${ARCH} -isysroot ${SDK_PATH} -target ${TARGET}"

    local ASM_FLAGS=(--enable-neon)
    [[ "${ARCH}" == "x86_64" ]] && ASM_FLAGS=(--disable-asm --disable-neon)

    local WORK_DIR="${BUILD_DIR}/work/${KEY}"
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"

    "${FFMPEG_SRC}/configure" \
        --prefix="${INSTALL_DIR}" \
        --enable-cross-compile \
        --target-os=darwin \
        --arch="${ARCH}" \
        --cc="/usr/bin/clang" \
        --extra-cflags="${CFLAGS}" \
        --extra-ldflags="${LDFLAGS}" \
        "${ASM_FLAGS[@]}" \
        "${COMMON_FLAGS[@]}" \
        2>&1 | tail -5

    make -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    make install 2>&1 | tail -3

    echo "✓ ${KEY} → ${INSTALL_DIR}"
}

make_framework() {
    local LIB="$1" FW="$2" PLATFORM="$3"
    shift 3
    local KEYS=("$@")

    local FW_DIR="${BUILD_DIR}/frameworks/${PLATFORM}/${FW}.framework"
    rm -rf "${FW_DIR}"
    mkdir -p "${FW_DIR}/Headers" "${FW_DIR}/Modules"

    # Headers from first arch
    cp -R "${BUILD_DIR}/thin/${KEYS[1]}/include/${LIB}/"* "${FW_DIR}/Headers/"

    # Remove platform-specific hwcontext headers that require unavailable
    # system headers (CUDA, Vulkan, DRM, VAAPI, VDPAU, MediaCodec, OpenCL).
    # We only need hwcontext.h (base) and hwcontext_videotoolbox.h on Apple.
    rm -f "${FW_DIR}/Headers/hwcontext_cuda.h" \
          "${FW_DIR}/Headers/hwcontext_d3d11va.h" \
          "${FW_DIR}/Headers/hwcontext_d3d12va.h" \
          "${FW_DIR}/Headers/hwcontext_drm.h" \
          "${FW_DIR}/Headers/hwcontext_dxva2.h" \
          "${FW_DIR}/Headers/hwcontext_mediacodec.h" \
          "${FW_DIR}/Headers/hwcontext_opencl.h" \
          "${FW_DIR}/Headers/hwcontext_qsv.h" \
          "${FW_DIR}/Headers/hwcontext_vaapi.h" \
          "${FW_DIR}/Headers/hwcontext_vdpau.h" \
          "${FW_DIR}/Headers/hwcontext_vulkan.h"

    # Lipo
    local INPUTS=()
    for K in "${KEYS[@]}"; do
        INPUTS+=("${BUILD_DIR}/thin/${K}/lib/${LIB}.a")
    done
    lipo -create "${INPUTS[@]}" -output "${FW_DIR}/${FW}"

    # Module map
    cat > "${FW_DIR}/Modules/module.modulemap" << EOF
framework module ${FW} [system] {
    umbrella "."
    exclude header "d3d11va.h"
    exclude header "d3d12va.h"
    exclude header "dxva2.h"
    exclude header "qsv.h"
    exclude header "vdpau.h"
    export *
}
EOF
    # Info.plist
    cat > "${FW_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>${FW}</string>
<key>CFBundleIdentifier</key><string>com.steelplayer.${FW}</string>
<key>CFBundleName</key><string>${FW}</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
EOF
}

make_xcframeworks() {
    echo ""
    echo "━━━ Creating XCFrameworks ━━━"

    local PAIRS=("libavcodec:Libavcodec" "libavformat:Libavformat" "libavutil:Libavutil" "libswresample:Libswresample")

    for PAIR in "${PAIRS[@]}"; do
        local LIB="${PAIR%%:*}"
        local FW="${PAIR##*:}"

        make_framework "$LIB" "$FW" "ios"          ios-arm64
        make_framework "$LIB" "$FW" "isimulator"   isimulator-arm64 isimulator-x86_64
        make_framework "$LIB" "$FW" "tvos"         tvos-arm64
        make_framework "$LIB" "$FW" "tvsimulator"  tvsimulator-arm64 tvsimulator-x86_64
        make_framework "$LIB" "$FW" "macos"        macos-arm64 macos-x86_64

        local XCF="${OUTPUT_DIR}/${FW}.xcframework"
        rm -rf "${XCF}"

        echo "  → ${FW}.xcframework"
        xcodebuild -create-xcframework \
            -framework "${BUILD_DIR}/frameworks/ios/${FW}.framework" \
            -framework "${BUILD_DIR}/frameworks/isimulator/${FW}.framework" \
            -framework "${BUILD_DIR}/frameworks/tvos/${FW}.framework" \
            -framework "${BUILD_DIR}/frameworks/tvsimulator/${FW}.framework" \
            -framework "${BUILD_DIR}/frameworks/macos/${FW}.framework" \
            -output "${XCF}" 2>&1 | tail -1
        echo "  ✓ ${FW}.xcframework"
    done
}

# ─────────────────────────────────────────────────────────

if [[ "$1" == "clean" ]]; then
    echo "Cleaning..."
    rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}/"*.xcframework
    echo "✓ Clean"
    exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║  FFmpegBuild — Minimal FFmpeg Build  ║"
echo "║  No network, no TLS, no encoders     ║"
echo "║  VideoToolbox HW + Metal ready       ║"
echo "╚══════════════════════════════════════╝"

fetch_ffmpeg

# Build all platform/arch combinations
build_one ios-arm64          iphoneos         arm64  arm64-apple-ios16.0                    16.0
build_one isimulator-arm64   iphonesimulator  arm64  arm64-apple-ios16.0-simulator          16.0
build_one isimulator-x86_64  iphonesimulator  x86_64 x86_64-apple-ios16.0-simulator         16.0
build_one tvos-arm64         appletvos        arm64  arm64-apple-tvos16.0                   16.0
build_one tvsimulator-arm64  appletvsimulator arm64  arm64-apple-tvos16.0-simulator         16.0
build_one tvsimulator-x86_64 appletvsimulator x86_64 x86_64-apple-tvos16.0-simulator        16.0
build_one macos-arm64        macosx           arm64  arm64-apple-macos14.0                  14.0
build_one macos-x86_64       macosx           x86_64 x86_64-apple-macos14.0                 14.0

make_xcframeworks

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✓ Build complete!                   ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Sizes:"
for xcf in "${OUTPUT_DIR}"/*.xcframework; do
    [[ -d "$xcf" ]] && echo "  $(du -sh "$xcf" | cut -f1)  $(basename $xcf)"
done
