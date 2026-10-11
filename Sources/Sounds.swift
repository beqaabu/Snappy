import AppKit

// MARK: - Sounds

enum Sounds {
    /// The camera shutter, for image captures.
    static func shutter() {
        guard Prefs.playSound else { return }
        let url = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif")
        (NSSound(contentsOf: url, byReference: true) ?? NSSound(named: "Grab"))?.play()
    }

    /// A short scanner "bee-dip" after text was copied: a quick rising sweep, then a tiny high blip.
    static func scan() {
        guard Prefs.playSound else { return }
        scanSound.stop()
        scanSound.play()
    }

    /// A soft low tone when a selection had no text, so it doesn't sound like success.
    static func noText() {
        guard Prefs.playSound else { return }
        noTextSound.stop()
        noTextSound.play()
    }

    private static let scanSound = tone([(from: 950, to: 2200, seconds: 0.15), (from: 0, to: 0, seconds: 0.03), (from: 2400, to: 2400, seconds: 0.05)])
    private static let noTextSound = tone([(from: 420, to: 330, seconds: 0.16)])

    /// Synthesizes sine glides (frequency 0 = silence) into a WAV and wraps it in an NSSound.
    private static func tone(_ segments: [(from: Double, to: Double, seconds: Double)]) -> NSSound {
        let rate = 44_100.0
        var samples: [Int16] = []
        var phase = 0.0
        for segment in segments {
            let count = Int(segment.seconds * rate)
            let fade = min(Int(0.006 * rate), count / 2) // soft edges, no clicks
            for i in 0..<count {
                guard segment.from > 0 else { samples.append(0); continue }
                let t = Double(i) / Double(count)
                let frequency = segment.from + (segment.to - segment.from) * t
                phase += 2 * .pi * frequency / rate
                let envelope = min(1, Double(i) / Double(fade), Double(count - i) / Double(fade))
                samples.append(Int16(sin(phase) * envelope * 0.22 * Double(Int16.max)))
            }
        }
        return NSSound(data: wav(samples, rate: Int(rate)))!
    }

    private static func wav(_ samples: [Int16], rate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        samples.forEach { append($0) }
        return data
    }
}
