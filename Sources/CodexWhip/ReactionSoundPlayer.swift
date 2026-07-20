import AVFoundation
import Foundation

@MainActor
final class ReactionSoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var referenceWhipPlayers: [AVAudioPlayer] = []
    private var referenceWhipCleanupTasks: [Task<Void, Never>] = []

    init() {
        format = AVAudioFormat(
            standardFormatWithSampleRate: ReactionSoundFactory.sampleRate,
            channels: 1
        )!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.72
        engine.prepare()
    }

    func play(_ kind: ReactionKind) {
        stop()

        if kind == .whip, playReferenceWhipSequence() {
            return
        }

        guard let buffer = ReactionSoundFactory.makeBuffer(for: kind) else { return }

        do {
            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } catch {
            NSLog("Codex Whip could not start audio output: %@", error.localizedDescription)
        }
    }

    func stop() {
        referenceWhipCleanupTasks.forEach { $0.cancel() }
        referenceWhipCleanupTasks.removeAll()
        referenceWhipPlayers.forEach { $0.stop() }
        referenceWhipPlayers.removeAll()
        player.stop()
    }

    private func playReferenceWhipSequence() -> Bool {
        guard let url = WhipReferenceSound.url else { return false }

        do {
            let players = try (0..<WhipPhysics.strikeCount).map { _ in
                let referencePlayer = try AVAudioPlayer(contentsOf: url)
                referencePlayer.volume = WhipReferenceSound.volume
                referencePlayer.prepareToPlay()
                return referencePlayer
            }
            guard let firstPlayer = players.first else { return false }

            let deviceStartTime = firstPlayer.deviceCurrentTime
            for (strikeIndex, referencePlayer) in players.enumerated() {
                let startDelay = WhipReferenceSound.playbackStartTime(
                    strikeIndex: strikeIndex
                )
                guard referencePlayer.play(atTime: deviceStartTime + startDelay) else {
                    players.forEach { $0.stop() }
                    return false
                }
                scheduleFadeOut(of: referencePlayer, after: startDelay)
            }
            referenceWhipPlayers = players
            return true
        } catch {
            NSLog("Codex Whip could not play the reference whip sequence: %@", error.localizedDescription)
            return false
        }
    }

    private func scheduleFadeOut(
        of referencePlayer: AVAudioPlayer,
        after startDelay: TimeInterval
    ) {
        let task = Task { [weak self] in
            let fadeDelay = startDelay + WhipReferenceSound.fadeStart
            try? await Task.sleep(nanoseconds: UInt64(fadeDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            referencePlayer.setVolume(
                0,
                fadeDuration: WhipReferenceSound.fadeDuration
            )
            try? await Task.sleep(
                nanoseconds: UInt64(WhipReferenceSound.fadeDuration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            referencePlayer.stop()
            self?.referenceWhipPlayers.removeAll { $0 === referencePlayer }
        }
        referenceWhipCleanupTasks.append(task)
    }
}

enum WhipReferenceSound {
    static let crackPeakOffset: TimeInterval = 0.415
    static let playbackDuration = WhipPhysics.cycleDuration - 0.015
    static let fadeDuration: TimeInterval = 0.075
    static let fadeStart = playbackDuration - fadeDuration
    static let volume: Float = 0.82

    static func playbackStartTime(strikeIndex: Int) -> TimeInterval {
        max(
            0,
            ReactionSoundFactory.whipCrackTime(strikeIndex: strikeIndex)
                - crackPeakOffset
        )
    }

    static var url: URL? {
        if let appResource = Bundle.main.url(
            forResource: "whip-crack",
            withExtension: "mp3"
        ) {
            return appResource
        }

        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "whip-crack", withExtension: "mp3")
        #else
        return nil
        #endif
    }
}

enum ReactionSoundFactory {
    static let sampleRate = 44_100.0
    static let whipIntro: TimeInterval = 0.18
    static let whipCrackProgress = 0.64

    static func makeBuffer(for kind: ReactionKind) -> AVAudioPCMBuffer? {
        switch kind {
        case .praise:
            return makePraiseBuffer()
        case .whip:
            return makeWhipBuffer()
        }
    }

    static func whipCrackTime(strikeIndex: Int) -> TimeInterval {
        whipIntro + WhipPhysics.cycleDuration * (Double(strikeIndex) + whipCrackProgress)
    }

    private static func makePraiseBuffer() -> AVAudioPCMBuffer? {
        let duration = 1.65
        guard let buffer = emptyBuffer(duration: duration),
              let samples = buffer.floatChannelData?[0] else {
            return nil
        }

        let notes: [(start: TimeInterval, frequency: Double, gain: Float)] = [
            (0.00, 659.25, 0.12),
            (0.14, 783.99, 0.115),
            (0.31, 1_046.50, 0.105)
        ]

        for frame in 0..<Int(buffer.frameLength) {
            let time = Double(frame) / sampleRate
            var sample = 0.0

            for note in notes where time >= note.start {
                let age = time - note.start
                let attack = min(age / 0.014, 1)
                let decay = exp(-age * 3.8)
                let phase = 2 * Double.pi * note.frequency * age
                let harmonic = sin(phase)
                    + 0.24 * sin(phase * 2)
                    + 0.08 * sin(phase * 3)
                sample += Double(note.gain) * attack * decay * harmonic
            }

            samples[frame] = Float(clamp(sample, limit: 0.82))
        }
        return buffer
    }

    private static func makeWhipBuffer() -> AVAudioPCMBuffer? {
        let duration = 2.16
        guard let buffer = emptyBuffer(duration: duration),
              let samples = buffer.floatChannelData?[0] else {
            return nil
        }

        var noise = DeterministicNoise(seed: 0xC0DE_5748)
        var smoothedNoise = 0.0

        for frame in 0..<Int(buffer.frameLength) {
            let time = Double(frame) / sampleRate
            let rawNoise = noise.next()
            smoothedNoise += (rawNoise - smoothedNoise) * 0.055
            let brightNoise = rawNoise - smoothedNoise
            var sample = 0.0

            for strikeIndex in 0..<WhipPhysics.strikeCount {
                let crackTime = whipCrackTime(strikeIndex: strikeIndex)
                let timeBeforeCrack = crackTime - time

                if timeBeforeCrack > 0, timeBeforeCrack < 0.09 {
                    let sweep = 1 - timeBeforeCrack / 0.09
                    sample += brightNoise * 0.028 * sweep * sweep
                }

                let crackAge = time - crackTime
                if crackAge >= 0, crackAge < 0.065 {
                    let slapEnvelope = exp(-crackAge * 105)
                    let crispEdge = sin(2 * Double.pi * 1_180 * crackAge)
                        + 0.42 * sin(2 * Double.pi * 1_760 * crackAge)
                    sample += brightNoise * 0.64 * slapEnvelope
                    sample += crispEdge * 0.075 * exp(-crackAge * 145)
                }

                // A tiny delayed edge gives the crack a papery "pa" quality
                // without turning it into a separate echo or a bassy impact.
                let reboundAge = crackAge - 0.014
                if reboundAge >= 0, reboundAge < 0.04 {
                    sample += brightNoise * 0.20 * exp(-reboundAge * 125)
                }
            }

            samples[frame] = Float(clamp(sample, limit: 0.90))
        }
        return buffer
    }

    private static func emptyBuffer(duration: TimeInterval) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(ceil(duration * sampleRate))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }
        buffer.frameLength = frameCount
        return buffer
    }

    private static func clamp(_ sample: Double, limit: Double) -> Double {
        min(max(sample, -limit), limit)
    }
}

private struct DeterministicNoise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let normalized = Double(state >> 11) / Double(UInt64.max >> 11)
        return normalized * 2 - 1
    }
}
