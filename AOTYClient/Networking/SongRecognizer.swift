import Foundation
import Accelerate
import AVFoundation

/// Hears a song through the mic and asks Shazam what it is: the same fingerprint method as
/// SongRec (used by the Live Scrobbler), so it needs no ShazamKit permission from Apple.
enum SongRecognizer {
    struct Match: Equatable {
        let title: String
        let artist: String
        let album: String?
        let cover: URL?
    }

    // MARK: Shazam request

    static func identify(_ samples: ArraySlice<Int16>) async throws -> Match? {
        let sig = Signature.make(Array(samples))
        let url = URL(string: "https://amp.shazam.com/discovery/v5/en-US/US/iphone/-/tag/\(UUID().uuidString)/\(UUID().uuidString)"
            + "?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3&sharehub=true&hubv5minorversion=v5.1&hidelb=true&video=v3")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("IPHONE", forHTTPHeaderField: "X-Shazam-Platform")
        req.setValue("14.1.0", forHTTPHeaderField: "X-Shazam-AppVersion")
        req.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        req.setValue("Shazam/3685 CFNetwork/1197 Darwin/20.0.0", forHTTPHeaderField: "User-Agent")
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let body: [String: Any] = [
            "timezone": TimeZone.current.identifier,
            "signature": ["uri": sig.uri, "samplems": sig.ms],
            "timestamp": now,
            "context": [String: Any](),
            "geolocation": [String: Any](),
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let track = obj["track"] as? [String: Any],
              let title = track["title"] as? String, let artist = track["subtitle"] as? String else { return nil }
        var album: String?
        for section in (track["sections"] as? [[String: Any]]) ?? [] {
            for m in (section["metadata"] as? [[String: Any]]) ?? [] where (m["title"] as? String) == "Album" {
                album = m["text"] as? String
            }
        }
        let images = track["images"] as? [String: Any]
        let cover = ((images?["coverarthq"] ?? images?["coverart"]) as? String).flatMap(URL.init(string:))
        return Match(title: title, artist: artist, album: album, cover: cover)
    }

    // MARK: Fingerprint (port of SongRec / shazamio's signature generator)

    struct Signature {
        let uri: String
        let ms: Int

        /// 16 kHz mono signed 16-bit samples → Shazam "data:audio/vnd.shazam.sig" URI.
        static func make(_ samples: [Int16]) -> Signature {
            let g = Generator()
            var i = 0
            while i + 128 <= samples.count {
                g.process(samples[i..<i + 128])
                i += 128
            }
            let n = i
            return Signature(uri: "data:audio/vnd.shazam.sig;base64," + encode(peaks: g.peaks, samples: n).base64EncodedString(),
                             ms: n * 1000 / 16000)
        }

        struct Peak { let pass: Int; let magnitude: Int; let bin: Int }

        final class Generator {
            private var ring = [Float](repeating: 0, count: 2048)
            private var ringPos = 0
            private var ffts = [[Float]](repeating: [Float](repeating: 0, count: 1025), count: 256)
            private var fftPos = 0
            private var spread = [[Float]](repeating: [Float](repeating: 0, count: 1025), count: 256)
            private var spreadPos = 0
            private var spreadWritten = 0
            var peaks: [Int: [Peak]] = [:]

            private let window: [Float] = (1...2048).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / 2049)) }
            private let dft = try! vDSP.DiscreteFourierTransform(count: 2048, direction: .forward,
                                                                 transformType: .complexComplex, ofType: Float.self)
            private let zeros = [Float](repeating: 0, count: 2048)

            private func wrap(_ i: Int) -> Int { ((i % 256) + 256) % 256 }

            func process(_ batch: ArraySlice<Int16>) {
                // FFT of the last 2048 samples, every 128 new ones.
                for (k, s) in batch.enumerated() { ring[ringPos + k] = Float(s) }
                ringPos = (ringPos + batch.count) % 2048
                let excerpt = Array(ring[ringPos...] + ring[..<ringPos])
                let out = dft.transform(inputReal: vDSP.multiply(excerpt, window), inputImaginary: zeros)
                var mags = [Float](repeating: 0, count: 1025)
                for b in 0..<1025 {
                    mags[b] = max((out.real[b] * out.real[b] + out.imaginary[b] * out.imaginary[b]) / 131072, 1e-10)
                }
                ffts[fftPos] = mags
                fftPos = (fftPos + 1) % 256

                spreadPeaks(mags)
                if spreadWritten >= 46 { findPeaks() }
            }

            private func spreadPeaks(_ last: [Float]) {
                var s = last
                for p in 0..<1022 { s[p] = max(last[p], last[p + 1], last[p + 2]) }
                let i1 = wrap(spreadPos - 1), i2 = wrap(spreadPos - 3), i3 = wrap(spreadPos - 6)
                var a1 = s, a2 = s, a3 = s
                for p in 0..<1025 {
                    a1[p] = max(s[p], spread[i1][p])
                    a2[p] = max(a1[p], spread[i2][p])
                    a3[p] = max(a2[p], spread[i3][p])
                }
                spread[i1] = a1; spread[i2] = a2; spread[i3] = a3
                spread[spreadPos] = s
                spreadPos = (spreadPos + 1) % 256
                spreadWritten += 1
            }

            private func findPeaks() {
                let f46 = ffts[wrap(fftPos - 46)]
                let s49 = spread[wrap(spreadPos - 49)]
                let others = [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249].map { spread[wrap(spreadPos + $0)] }
                for bin in 10..<1015 {
                    let v = f46[bin]
                    guard v >= 1.0 / 64, v >= s49[bin - 1] else { continue }
                    var maxNeighbor: Float = 0
                    for o in [-10, -7, -3, 1, 2, 5, 8] { maxNeighbor = max(s49[bin + o], maxNeighbor) }
                    guard v > maxNeighbor else { continue }
                    var maxOther = maxNeighbor
                    for o in others { maxOther = max(o[bin - 1], maxOther) }
                    guard v > maxOther else { continue }

                    func mag(_ x: Float) -> Double { log(Double(max(1.0 / 64, x))) * 1477.3 + 6144 }
                    let m = mag(v), before = mag(f46[bin - 1]), after = mag(f46[bin + 1])
                    let v1 = m * 2 - before - after
                    guard v1 > 0 else { continue }
                    let v2 = (after - before) * 32 / v1
                    let corrected = Double(bin) * 64 + v2
                    let hz = corrected * (16000.0 / 2 / 1024 / 64)
                    let band: Int
                    switch hz {
                    case 250..<520: band = 0
                    case 520..<1450: band = 1
                    case 1450..<3500: band = 2
                    case 3500...5500: band = 3
                    default: continue
                    }
                    peaks[band, default: []].append(Peak(pass: spreadWritten - 46, magnitude: Int(m), bin: Int(corrected)))
                }
            }
        }

        static func encode(peaks: [Int: [Peak]], samples: Int) -> Data {
            var contents = Data()
            for band in peaks.keys.sorted() {
                var buf = Data()
                var pass = 0
                for p in peaks[band]! {
                    if p.pass - pass >= 255 {
                        buf.append(0xFF); buf.appendLE(UInt32(p.pass)); pass = p.pass
                    }
                    buf.append(UInt8(p.pass - pass))
                    buf.appendLE(UInt16(clamping: p.magnitude))
                    buf.appendLE(UInt16(clamping: p.bin))
                    pass = p.pass
                }
                contents.appendLE(UInt32(0x6003_0040 + band))
                contents.appendLE(UInt32(buf.count))
                contents.append(buf)
                contents.append(Data(count: (4 - buf.count % 4) % 4))
            }
            var body = Data()
            body.appendLE(UInt32(0x4000_0000))
            body.appendLE(UInt32(contents.count + 8))
            body.append(contents)

            // 48-byte header; the CRC covers everything after its first 8 bytes.
            var rest = Data()
            rest.appendLE(UInt32(contents.count + 8))                    // size minus header
            rest.appendLE(UInt32(0x9411_9C00))                           // magic 2
            rest.append(Data(count: 12))
            rest.appendLE(UInt32(3) << 27)                               // 16 kHz
            rest.append(Data(count: 8))
            rest.appendLE(UInt32(samples + Int(16000 * 0.24)))
            rest.appendLE(UInt32((15 << 19) + 0x40000))
            rest.append(body)

            var out = Data()
            out.appendLE(UInt32(0xCAFE_2580))
            out.appendLE(crc32(rest))
            out.append(rest)
            return out
        }

        private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            return c
        }

        static func crc32(_ data: Data) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
            return c ^ 0xFFFF_FFFF
        }
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) }
    }
}

// MARK: - Microphone

/// Records the mic as 16 kHz mono 16-bit samples.
final class MicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Int16] = []

    var collected: [Int16] { lock.lock(); defer { lock.unlock() }; return samples }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: target) else { throw CocoaError(.featureUnsupported) }
        let ratio = 16000 / inFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let self, let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            guard err == nil, let ch = out.int16ChannelData else { return }
            let chunk = UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength))
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
