import Foundation
import AVFoundation

/// Keeps the app alive in the background (Delta-style): plays a silent
/// looping WAV with the audio session in playback + mix mode, so the game's
/// audio keeps playing and iOS doesn't suspend us.
final class BackgroundAudio {
    static let shared = BackgroundAudio()

    private var player: AVAudioPlayer?

    func ensureRunning() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // keep going; the player may still work
        }
        if let p = player {
            if !p.isPlaying { p.play() }
            return
        }
        guard let url = Self.silentWavURL() else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.02
            p.play()
            player = p
        } catch {
        }
    }

    private static func silentWavURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bola_silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 8000
        let samples = sampleRate * 2
        let dataSize = samples * 2
        var d = Data()
        func app32(_ v: UInt32) {
            d.append(UInt8(v & 0xFF))
            d.append(UInt8((v >> 8) & 0xFF))
            d.append(UInt8((v >> 16) & 0xFF))
            d.append(UInt8((v >> 24) & 0xFF))
        }
        func app16(_ v: UInt16) {
            d.append(UInt8(v & 0xFF))
            d.append(UInt8((v >> 8) & 0xFF))
        }
        d.append(contentsOf: Array("RIFF".utf8))
        app32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        app32(16)
        app16(1)
        app16(1)
        app32(UInt32(sampleRate))
        app32(UInt32(sampleRate * 2))
        app16(2)
        app16(16)
        d.append(contentsOf: Array("data".utf8))
        app32(UInt32(dataSize))
        d.append(Data(count: dataSize))
        do {
            try d.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
