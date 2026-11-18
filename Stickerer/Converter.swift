import AVFoundation
import UIKit
import VideoToolbox
import libwebp

struct Sticker: Identifiable {
    var id = UUID()
    let webp: Data
    let firstFrame: UIImage
    var fits: Bool { webp.count <= Converter.maxBytes }
}

enum Converter {
    static let maxBytes = 500 * 1024      // WhatsApp animated sticker limit
    static let maxSeconds = 10.0
    static let side = 512
    static let baseFPS = 15.0   // frames are extracted once at this rate; cheaper rungs just skip frames
    // Progressively cheaper settings until the file fits under 500 KB.
    static let attempts: [(fps: Double, q: Double)] = [(15, 0.7), (15, 0.5), (12, 0.4), (10, 0.3), (8, 0.2)]

    static func download(_ url: URL) async throws -> URL {
        let tmp: URL, resp: URLResponse
        do {
            (tmp, resp) = try await URLSession.shared.download(from: url)
        } catch let e as URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw StickerError.message("No internet connection.")
            case .cannotFindHost, .dnsLookupFailed, .badURL, .unsupportedURL:
                throw StickerError.message("Could not find anything at that link.")
            case .timedOut:
                throw StickerError.message("The link took too long to respond.")
            default:
                throw StickerError.message("Could not load that link (\(e.localizedDescription)).")
            }
        }
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw StickerError.message(h.statusCode == 404
                ? "No video or GIF found at that link (404)."
                : "Could not load that link (HTTP \(h.statusCode)).")
        }
        let type = resp.mimeType?.lowercased() ?? ""
        let head = (try? FileHandle(forReadingFrom: tmp).read(upToCount: 12)) ?? Data()
        let isGIF = head.starts(with: Data("GIF8".utf8))
        let isMP4 = head.count >= 8 && head[4..<8] == Data("ftyp".utf8)
        if !isGIF, !isMP4 {
            if type.hasPrefix("image/") {
                throw StickerError.message("That link is an image, not a video or GIF.")
            }
            if type.hasPrefix("text/") || head.first == UInt8(ascii: "<") {
                throw StickerError.message("No video or GIF found at that link. Paste a direct link to the file.")
            }
            if !type.hasPrefix("video/") && type != "application/octet-stream" {
                throw StickerError.message("That link does not point to a video or GIF.")
            }
        }
        var ext = url.pathExtension.lowercased()
        if isGIF {
            ext = "gif"
        } else if !["mp4", "mov", "m4v"].contains(ext) {
            ext = "mp4"
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Converts `parts` equal slices of the video (1 = the whole clip) into animated 512x512 WebP stickers.
    static func convert(videoFile: URL, cover: Bool, parts: Int, status: @escaping (String) -> Void) async throws -> [Sticker] {
        let isGIF = videoFile.pathExtension == "gif"
        let asset = AVURLAsset(url: videoFile)
        let gif = isGIF ? try gifTimeline(videoFile) : nil
        let total = isGIF ? gif!.total : ((try? await asset.load(.duration).seconds) ?? 0)
        guard total.isFinite, total > 0 else { throw StickerError.message("That file could not be read as a video or GIF (unsupported format?).") }
        let length = min(total, maxSeconds * Double(parts))
        let slice = length / Double(parts)

        var out: [Sticker] = []
        for p in 0..<parts {
            let start = slice * Double(p)
            let label = parts > 1 ? "Clip \(p + 1)/\(parts)" : "Encoding"

            status("\(label)… (reading video)")
            let t0 = Date()
            let frames = try await Task.detached {
                if let gif { return try extractGIFFrames(gif, start: start, length: slice, cover: cover) }
                return try extractFrames(asset: asset, start: start, length: slice, cover: cover)
            }.value
            print("[Stickerer] extracted \(frames.count) frames in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
            guard let firstData = frames.first, let first = image(fromRGBA: firstData) else {
                throw StickerError.message("Could not read the video.")
            }

            var best: Data?
            for (i, a) in attempts.enumerated() {
                status("\(label)… (try \(i + 1))")
                let t1 = Date()
                // Frames are shared across tries; lower-fps rungs just pick a subset.
                let n = max(1, Int(slice * a.fps))
                let picked = (0..<n).map { frames[min(frames.count - 1, Int((Double($0) * baseFPS / a.fps).rounded()))] }
                let data = try await Task.detached { try encode(picked, fps: a.fps, quality: a.q) }.value
                print("[Stickerer] try \(i + 1): \(Int(a.fps))fps q\(a.q) -> \(data.count / 1024) KB in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
                best = data
                if data.count <= maxBytes { break }
            }
            guard let data = best else { throw StickerError.message("Conversion failed.") }
            out.append(Sticker(webp: data, firstFrame: first))
        }
        return out
    }

    /// Reads the clip once, sequentially (hardware decoder), and returns `baseFPS` frames as 512x512 non-premultiplied RGBA.
    private static func extractFrames(asset: AVAsset, start: Double, length: Double, cover: Bool) throws -> [Data] {
        guard let track = asset.tracks(withMediaType: .video).first else { throw StickerError.message("No video track.") }
        let t = track.preferredTransform
        let orientation: UIImage.Orientation =
            t.b == 1 && t.c == -1 ? .right :
            t.b == -1 && t.c == 1 ? .left :
            t.a == -1 && t.d == -1 ? .down : .up

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       duration: CMTime(seconds: length, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? StickerError.message("Could not read the video.") }

        let count = max(1, Int(length * baseFPS))
        var frames: [Data] = []
        frames.reserveCapacity(count)
        var prev: CVPixelBuffer?

        func emit(_ buf: CVPixelBuffer) {
            var cg: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buf, options: nil, imageOut: &cg)
            if let cg { frames.append(rgba(render(cg, orientation: orientation, cover: cover))) }
        }

        // Sample-and-hold: the frame shown at time t is the latest sample at or before t.
        while frames.count < count, let sample = output.copyNextSampleBuffer() {
            guard let buf = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds - start
            while frames.count < count, Double(frames.count) / baseFPS < pts - 1e-6 { emit(prev ?? buf) }
            prev = buf
        }
        while frames.count < count, let prev { emit(prev) }
        return frames
    }

    private struct GIFTimeline {
        let source: CGImageSource
        let starts: [Double]   // start time of each frame
        let total: Double
    }

    private static func gifTimeline(_ file: URL) throws -> GIFTimeline {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw StickerError.message("Could not read the GIF.")
        }
        var starts: [Double] = [], t = 0.0
        for i in 0..<CGImageSourceGetCount(src) {
            starts.append(t)
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let g = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            var d = (g?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (g?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            if d < 0.02 { d = 0.1 }   // browsers treat tiny delays as 100 ms
            t += d
        }
        return GIFTimeline(source: src, starts: starts, total: t)
    }

    private static func extractGIFFrames(_ gif: GIFTimeline, start: Double, length: Double, cover: Bool) throws -> [Data] {
        let count = max(1, Int(length * baseFPS))
        var cache: [Int: Data] = [:]
        return try (0..<count).map { n in
            let t = start + Double(n) / baseFPS
            let idx = max(0, (gif.starts.lastIndex { $0 <= t + 1e-6 }) ?? 0)
            if let d = cache[idx] { return d }
            guard let cg = CGImageSourceCreateImageAtIndex(gif.source, idx, nil) else { throw StickerError.message("Could not read the GIF.") }
            let d = rgba(render(cg, orientation: .up, cover: cover))
            cache[idx] = d
            return d
        }
    }

    /// 512x512 transparent canvas; "contain" pads, "cover" crops.
    private static func render(_ cg: CGImage, orientation: UIImage.Orientation, cover: Bool) -> CGImage {
        let canvas = CGFloat(side)
        let rotated = orientation == .left || orientation == .right
        let w = CGFloat(rotated ? cg.height : cg.width), h = CGFloat(rotated ? cg.width : cg.height)
        let s = cover ? max(canvas / w, canvas / h) : min(canvas / w, canvas / h)
        let rect = CGRect(x: (canvas - w * s) / 2, y: (canvas - h * s) / 2, width: w * s, height: h * s)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas), format: fmt).image { _ in
            UIImage(cgImage: cg, scale: 1, orientation: orientation).draw(in: rect)
        }.cgImage!
    }

    private static func rgba(_ cg: CGImage) -> Data {
        var data = Data(count: side * side * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            // libwebp wants straight (non-premultiplied) alpha.
            let px = raw.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: px.count, by: 4) {
                let a = Int(px[i + 3])
                if a != 255 && a != 0 {
                    px[i] = UInt8(min(255, Int(px[i]) * 255 / a))
                    px[i + 1] = UInt8(min(255, Int(px[i + 1]) * 255 / a))
                    px[i + 2] = UInt8(min(255, Int(px[i + 2]) * 255 / a))
                }
            }
        }
        return data
    }

    private static func image(fromRGBA data: Data) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        // Redraw into a standard premultiplied bitmap so PNG round-trips (library thumbnails) look identical.
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// Real animated WebP via libwebp's WebPAnimEncoder: only the changed region of each frame is stored.
    private static func encode(_ frames: [Data], fps: Double, quality: Double) throws -> Data {
        var opts = WebPAnimEncoderOptions()
        guard WebPAnimEncoderOptionsInit(&opts) != 0 else { throw StickerError.message("WebP encoding failed.") }
        opts.anim_params.loop_count = 0
        guard let enc = WebPAnimEncoderNew(Int32(side), Int32(side), &opts) else { throw StickerError.message("WebP encoding failed.") }
        defer { WebPAnimEncoderDelete(enc) }

        var cfg = WebPConfig()
        guard WebPConfigInit(&cfg) != 0 else { throw StickerError.message("WebP encoding failed.") }
        cfg.quality = Float(quality * 100)
        cfg.method = 3
        cfg.thread_level = 1

        for (i, f) in frames.enumerated() {
            var pic = WebPPicture()
            guard WebPPictureInit(&pic) != 0 else { throw StickerError.message("WebP encoding failed.") }
            defer { WebPPictureFree(&pic) }
            pic.use_argb = 1
            pic.width = Int32(side)
            pic.height = Int32(side)
            let ok = f.withUnsafeBytes { WebPPictureImportRGBA(&pic, $0.bindMemory(to: UInt8.self).baseAddress, Int32(side * 4)) }
            guard ok != 0, WebPAnimEncoderAdd(enc, &pic, Int32((Double(i) * 1000 / fps).rounded()), &cfg) != 0 else {
                throw StickerError.message("WebP encoding failed.")
            }
        }
        guard WebPAnimEncoderAdd(enc, nil, Int32((Double(frames.count) * 1000 / fps).rounded()), nil) != 0 else {
            throw StickerError.message("WebP encoding failed.")
        }
        var out = WebPData()
        WebPDataInit(&out)
        defer { WebPDataClear(&out) }
        guard WebPAnimEncoderAssemble(enc, &out) != 0, let bytes = out.bytes else { throw StickerError.message("WebP encoding failed.") }
        return Data(bytes: bytes, count: out.size)
    }
}
