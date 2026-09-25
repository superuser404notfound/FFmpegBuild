import Foundation
import Testing
import AetherLibavcodec
import AetherLibavformat
import AetherLibavutil

/// Proves an MPEG-TS audio PID is identified by its payload when its PMT label does not name
/// the codec, or names the wrong one (AetherEngine #641). Two separate gaps:
///
/// - The mpegts content probe runs the raw demuxers' probes over the payload, so a codec
///   whose raw demuxer is not in the build can never be confirmed, and the lenient mp3 probe
///   names the track instead (build.sh enables `dts`, `truehd` and `loas` for this).
/// - Stock `mpegts_set_stream_info()` asks for a content probe on a PID labelled 0x04 (MPEG-2
///   audio) or 0x0f (AAC), but takes 0x03 (MPEG-1 audio) at its word. A restreamer that
///   labels a DTS PID 0x03 therefore opens as mp3, every packet fails in mp3float with
///   "Header missing", and the track never produces a frame (build.sh
///   `patch_ffmpeg_mpegts_mpeg1_probe`).
///
/// Each case muxes a transport stream through the shipped mpegts muxer, rewrites the audio
/// PID's stream_type in the PMT, and opens the result the way a player does.
struct MPEGTSAudioProbeTests {

    private static let pmtPID = 0x1000

    /// The first 16 bytes of the reporter's DTS core frame: 48 kHz, 2012-byte frames of 512
    /// samples. The rest of each frame is filler, which is all the probe and the parser read.
    private static let dtsHeader: [UInt8] = [
        0x7f, 0xfe, 0x80, 0x01, 0xfc, 0x3c, 0x7d, 0xb2,
        0x77, 0x00, 0x0d, 0x3b, 0x80, 0x09, 0xef, 0x7b
    ]
    private static let dtsFrameSize = 2012

    /// MPEG-1 Layer II, 192 kbit/s, 48 kHz, no CRC: 576-byte frames of 1152 samples.
    private static let mp2Header: [UInt8] = [0xff, 0xfd, 0xa4, 0x00]
    private static let mp2FrameSize = 576

    /// Deterministic filler, so a failure reproduces byte for byte.
    private static func filler(_ count: Int, seed: UInt32) -> [UInt8] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
    }

    private static func frames(header: [UInt8], size: Int, count: Int) -> [[UInt8]] {
        (0..<count).map { header + filler(size - header.count, seed: UInt32($0) &+ 1) }
    }

    /// CRC-32/MPEG-2, the checksum a PSI section carries.
    private static func crc32MPEG(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in bytes {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04c1_1db7 : crc << 1
            }
        }
        return crc
    }

    /// Muxes `frames` as one audio stream of `codec` into a transport stream at `path`.
    private static func mux(codec: AVCodecID, sampleRate: Int32, frameSamples: Int64,
                            frames: [[UInt8]], to path: String) -> Bool {
        var ctxOut: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&ctxOut, nil, "mpegts", path) == 0,
              let ctx = ctxOut else { return false }
        defer { avformat_free_context(ctx) }
        guard let stream = avformat_new_stream(ctx, nil) else { return false }
        let par = stream.pointee.codecpar!
        par.pointee.codec_type = AVMEDIA_TYPE_AUDIO
        par.pointee.codec_id = codec
        par.pointee.sample_rate = sampleRate
        av_channel_layout_default(&par.pointee.ch_layout, 2)
        stream.pointee.time_base = AVRational(num: 1, den: sampleRate)

        guard avio_open(&ctx.pointee.pb, path, AVIO_FLAG_WRITE) >= 0 else { return false }
        defer { avio_closep(&ctx.pointee.pb) }
        guard avformat_write_header(ctx, nil) >= 0 else { return false }

        var pkt = av_packet_alloc()
        defer { av_packet_free(&pkt) }
        guard let packet = pkt else { return false }
        for (index, frame) in frames.enumerated() {
            guard av_new_packet(packet, Int32(frame.count)) >= 0 else { return false }
            frame.withUnsafeBytes { _ = memcpy(packet.pointee.data, $0.baseAddress!, frame.count) }
            packet.pointee.stream_index = 0
            packet.pointee.pts = Int64(index) * frameSamples
            packet.pointee.dts = packet.pointee.pts
            packet.pointee.duration = frameSamples
            guard av_interleaved_write_frame(ctx, packet) >= 0 else { return false }
        }
        return av_write_trailer(ctx) >= 0
    }

    /// Rewrites the stream_type of every elementary stream (there is one) in every PMT
    /// section and fixes the CRC.
    /// Returns how many sections were rewritten.
    private static func relabel(_ ts: inout [UInt8], streamType: UInt8) -> Int {
        var rewritten = 0
        for start in stride(from: 0, to: ts.count - 187, by: 188) {
            let pid = (Int(ts[start + 1] & 0x1f) << 8) | Int(ts[start + 2])
            guard pid == pmtPID, ts[start + 1] & 0x40 != 0 else { continue }
            let section = start + 5 + Int(ts[start + 4])
            let sectionLength = (Int(ts[section + 1] & 0x0f) << 8) | Int(ts[section + 2])
            let programInfoLength = (Int(ts[section + 10] & 0x0f) << 8) | Int(ts[section + 11])
            let crcAt = section + 3 + sectionLength - 4
            var entry = section + 12 + programInfoLength
            while entry < crcAt {
                let esInfoLength = (Int(ts[entry + 3] & 0x0f) << 8) | Int(ts[entry + 4])
                ts[entry] = streamType
                entry += 5 + esInfoLength
            }
            let crc = crc32MPEG(ts[section..<crcAt])
            ts[crcAt] = UInt8(crc >> 24)
            ts[crcAt + 1] = UInt8((crc >> 16) & 0xff)
            ts[crcAt + 2] = UInt8((crc >> 8) & 0xff)
            ts[crcAt + 3] = UInt8(crc & 0xff)
            rewritten += 1
        }
        return rewritten
    }

    /// What a player sees for the audio stream after the usual open and stream-info pass.
    private static func openedCodec(path: String) -> AVCodecID? {
        var ctxIn: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&ctxIn, path, nil, nil) == 0, let ctx = ctxIn else { return nil }
        defer { avformat_close_input(&ctxIn) }
        guard avformat_find_stream_info(ctx, nil) >= 0, ctx.pointee.nb_streams == 1 else { return nil }
        return ctx.pointee.streams[0]!.pointee.codecpar.pointee.codec_id
    }

    private static func codecAfterRelabel(codec: AVCodecID, sampleRate: Int32, frameSamples: Int64,
                                          frames: [[UInt8]], streamType: UInt8) throws -> AVCodecID? {
        let dir = FileManager.default.temporaryDirectory
        let path = dir.appendingPathComponent("mpegts-probe-\(UUID().uuidString).ts").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard mux(codec: codec, sampleRate: sampleRate, frameSamples: frameSamples,
                  frames: frames, to: path) else { return nil }
        var ts = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
        guard relabel(&ts, streamType: streamType) > 0 else { return nil }
        try Data(ts).write(to: URL(fileURLWithPath: path))
        return openedCodec(path: path)
    }

    @Test("a DTS PID labelled MPEG-1 audio opens as DTS")
    func dtsLabelledMPEG1() throws {
        let codec = try Self.codecAfterRelabel(
            codec: AV_CODEC_ID_DTS, sampleRate: 48_000, frameSamples: 512,
            frames: Self.frames(header: Self.dtsHeader, size: Self.dtsFrameSize, count: 40),
            streamType: 0x03)
        // Stock FFmpeg answers AV_CODEC_ID_MP3 here, straight from the PMT.
        #expect(codec == AV_CODEC_ID_DTS)
    }

    @Test("a DTS PID labelled private data opens as DTS")
    func dtsLabelledPrivateData() throws {
        // 0x06 without a descriptor names no codec, so mpegts probes the payload with every
        // raw demuxer in the build. Without the dts demuxer the mp3 probe wins on noise.
        let codec = try Self.codecAfterRelabel(
            codec: AV_CODEC_ID_DTS, sampleRate: 48_000, frameSamples: 512,
            frames: Self.frames(header: Self.dtsHeader, size: Self.dtsFrameSize, count: 40),
            streamType: 0x06)
        #expect(codec == AV_CODEC_ID_DTS)
    }

    @Test("the raw audio demuxers the mpegts probe needs are in the build",
          arguments: ["dts", "truehd", "loas"])
    func probeDemuxerPresent(name: String) {
        #expect(av_find_input_format(name) != nil)
    }

    @Test("genuine MPEG-1 Layer II labelled 0x03 stays MPEG audio")
    func mp2LabelledMPEG1() throws {
        // Control: passes on either build, so a broken fixture cannot read as a green patch.
        let codec = try Self.codecAfterRelabel(
            codec: AV_CODEC_ID_MP2, sampleRate: 48_000, frameSamples: 1152,
            frames: Self.frames(header: Self.mp2Header, size: Self.mp2FrameSize, count: 60),
            streamType: 0x03)
        #expect(codec == AV_CODEC_ID_MP2 || codec == AV_CODEC_ID_MP3)
    }
}
