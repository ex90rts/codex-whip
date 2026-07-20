import AVFoundation
import Foundation

enum ReactionSoundSelfCheck {
    static func run() -> Bool {
        guard let praise = ReactionSoundFactory.makeBuffer(for: .praise),
              let whip = ReactionSoundFactory.makeBuffer(for: .whip),
              let praisePeak = peakAmplitude(in: praise),
              let whipPeak = peakAmplitude(in: whip),
              let reference = referenceWhipMetadata() else {
            FileHandle.standardError.write(Data("Reaction sound self-check could not create buffers\n".utf8))
            return false
        }

        let crackPeaks = (0..<WhipPhysics.strikeCount).map { strikeIndex in
            windowPeak(
                in: whip,
                centeredAt: ReactionSoundFactory.whipCrackTime(strikeIndex: strikeIndex),
                radius: 0.035
            )
        }
        let referenceStarts = (0..<WhipPhysics.strikeCount).map {
            WhipReferenceSound.playbackStartTime(strikeIndex: $0)
        }
        let alignedReferencePeaks = referenceStarts.map {
            $0 + WhipReferenceSound.crackPeakOffset
        }
        let expectedCrackTimes = (0..<WhipPhysics.strikeCount).map {
            ReactionSoundFactory.whipCrackTime(strikeIndex: $0)
        }
        let passed = praisePeak > 0.08
            && praisePeak < 0.90
            && whipPeak > 0.18
            && whipPeak < 0.95
            && crackPeaks.allSatisfy { $0 > 0.18 }
            && reference.duration > WhipPhysics.animationDuration
            && reference.duration < 2.5
            && reference.channels == 2
            && zip(alignedReferencePeaks, expectedCrackTimes).allSatisfy {
                abs($0 - $1) < 0.001
            }
            && zip(referenceStarts, referenceStarts.dropFirst()).allSatisfy {
                $1 - $0 >= WhipReferenceSound.playbackDuration
            }

        let output = String(
            format: "Reaction sounds: praise peak %.2f, fallback whip peak %.2f, cracks [%.2f, %.2f, %.2f], reference %.2fs/%dch, starts [%.3f, %.3f, %.3f], aligned peaks [%.3f, %.3f, %.3f]\n",
            praisePeak,
            whipPeak,
            crackPeaks[0],
            crackPeaks[1],
            crackPeaks[2],
            reference.duration,
            reference.channels,
            referenceStarts[0],
            referenceStarts[1],
            referenceStarts[2],
            alignedReferencePeaks[0],
            alignedReferencePeaks[1],
            alignedReferencePeaks[2]
        )
        if passed {
            print(output, terminator: "")
        } else {
            FileHandle.standardError.write(Data(output.utf8))
            FileHandle.standardError.write(Data("Reaction sound self-check failed\n".utf8))
        }
        return passed
    }

    private static func referenceWhipMetadata() -> (duration: TimeInterval, channels: Int)? {
        guard let url = WhipReferenceSound.url,
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        return (player.duration, player.numberOfChannels)
    }

    private static func peakAmplitude(in buffer: AVAudioPCMBuffer) -> Double? {
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        return (0..<Int(buffer.frameLength))
            .map { abs(Double(samples[$0])) }
            .max()
    }

    private static func windowPeak(
        in buffer: AVAudioPCMBuffer,
        centeredAt time: TimeInterval,
        radius: TimeInterval
    ) -> Double {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let start = max(0, Int((time - radius) * ReactionSoundFactory.sampleRate))
        let end = min(Int(buffer.frameLength), Int((time + radius) * ReactionSoundFactory.sampleRate))
        guard start < end else { return 0 }
        return (start..<end).map { abs(Double(samples[$0])) }.max() ?? 0
    }
}
