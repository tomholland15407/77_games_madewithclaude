//
//  SoundManager.swift
//  A Banana Game
//
//  Generates the game's sound effects in code (no audio files needed) using a
//  tiny synthesizer. Every sound honors `isEnabled`, which the Settings screen
//  (Checkpoint C) will toggle. Call it from anywhere via `SoundManager.shared`.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class SoundManager {
    static let shared = SoundManager()

    /// Master on/off for all sound effects. Persisted so it sticks between launches.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: key) }
    }
    private let key = "soundEnabled"

    /// Transient mute used while a manual's live demo is on screen, so a demo that
    /// drives a game's real tap/win functions stays silent. Not persisted.
    @ObservationIgnored var suppressed = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let sampleRate = 44_100.0
    @ObservationIgnored private var isSetup = false

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    // MARK: - Public sound effects

    /// A quick pop — for tapping a banana / button.
    func tap() { schedule([tone(freqs: [660, 990], duration: 0.06, volume: 0.45)]) }

    /// A rising three-note arpeggio — for beating a level.
    func success() {
        schedule([
            tone(freqs: [523], duration: 0.12, volume: 0.5),   // C5
            tone(freqs: [659], duration: 0.12, volume: 0.5),   // E5
            tone(freqs: [784], duration: 0.20, volume: 0.5),   // G5
        ])
    }

    /// A low buzz — for a mistake ("too soon" / "too slow").
    func error() { schedule([tone(freqs: [150, 160], duration: 0.22, volume: 0.5)]) }

    /// A soft blip — each "3 · 2 · 1" countdown tick.
    func countdownTick() { schedule([tone(freqs: [700], duration: 0.08, volume: 0.4)]) }

    /// A bright chime — the moment a game starts / the "GO".
    func countdownGo() { schedule([tone(freqs: [1046], duration: 0.16, volume: 0.5)]) }

    /// A distinct musical note per pad — for the memory game (Simon-style).
    func padTone(_ index: Int) {
        let scale = [392.0, 523.0, 659.0, 784.0]   // G4, C5, E5, G5
        schedule([tone(freqs: [scale[index % scale.count]], duration: 0.2, volume: 0.5)])
    }

    // MARK: - Engine

    private func setupIfNeeded() {
        guard !isSetup else { return }
        isSetup = true
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            // .ambient = mixes with other audio and respects the mute switch.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            player.play()
        } catch {
            // If audio can't start, we just stay silent rather than crash.
        }
    }

    /// Plays buffers back-to-back (so a list of notes becomes a little melody).
    private func schedule(_ buffers: [AVAudioPCMBuffer?]) {
        guard isEnabled, !suppressed else { return }
        setupIfNeeded()
        guard engine.isRunning else { return }
        for case let buffer? in buffers {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    /// Builds a short tone with a gentle envelope so it doesn't click.
    private func tone(freqs: [Double], duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }

        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        let attack = 0.005   // 5 ms fade-in to avoid a click

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var value = 0.0
            for f in freqs { value += sin(2 * .pi * f * t) }
            value /= Double(freqs.count)

            // Envelope: quick attack, then decay to silence by the end.
            let progress = t / duration
            let env = t < attack ? (t / attack) : pow(1.0 - progress, 2.0)
            samples[i] = Float(value * env) * volume
        }
        return buffer
    }
}
