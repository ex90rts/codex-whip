import CoreGraphics
import Foundation

enum WhipPhysicsSelfCheck {
    static func run() -> Bool {
        var maximumHandleError: CGFloat = 0
        var maximumLashError: CGFloat = 0
        var strikeDiagnostics: [String] = []
        var didPass = true

        for elapsed in stride(
            from: 0.0,
            through: WhipPhysics.animationDuration,
            by: 1.0 / 120.0
        ) {
            let state = WhipPhysics.state(at: elapsed)
            maximumHandleError = max(
                maximumHandleError,
                abs(distance(state.handlePivot, state.handleTip) - WhipPhysics.handleLength)
            )
            maximumLashError = max(
                maximumLashError,
                WhipPhysics.maximumSegmentError(in: state)
            )
        }

        for strikeIndex in 0..<WhipPhysics.strikeCount {
            let cycleStart = Double(strikeIndex) * WhipPhysics.cycleDuration
            let windUp = peak(from: cycleStart + 0.04, through: cycleStart + 0.17)
            let snap = peak(from: cycleStart + 0.25, through: cycleStart + 0.48)
            let crack = peakCrack(from: cycleStart, through: cycleStart + WhipPhysics.cycleDuration)
            let speedRatio = snap.speed / max(windUp.speed, 1)

            strikeDiagnostics.append(
                String(
                    format: "strike %d: wind-up %.0f px/s, snap %.0f px/s (%.2fx), peak at %.3fs, crack %.2f",
                    strikeIndex + 1,
                    Double(windUp.speed),
                    Double(snap.speed),
                    Double(speedRatio),
                    snap.time - cycleStart,
                    crack
                )
            )
            didPass = didPass && speedRatio > 1.35 && snap.speed > 550 && crack > 0.08
        }

        let raisedHandle = WhipPhysics.state(at: WhipPhysics.cycleDuration * 0.38)
        let downwardStrike = WhipPhysics.state(at: WhipPhysics.cycleDuration * 0.56)
        let strikeDirection = CGPoint(
            x: downwardStrike.handleTip.x - downwardStrike.handlePivot.x,
            y: downwardStrike.handleTip.y - downwardStrike.handlePivot.y
        )
        let strikeAngle = atan2(strikeDirection.y, strikeDirection.x) * 180 / .pi
        var downwardLash = (delta: CGPoint(x: -.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude), progress: 0.56)
        for progress in stride(from: 0.56, through: 0.98, by: 0.02) {
            let state = WhipPhysics.state(at: WhipPhysics.cycleDuration * progress)
            let lashTip = state.lashPoints.last ?? state.handleTip
            let delta = CGPoint(
                x: lashTip.x - state.handleTip.x,
                y: lashTip.y - state.handleTip.y
            )
            if delta.y > downwardLash.delta.y {
                downwardLash = (delta, progress)
            }
        }
        let comesFromUpperLeft = raisedHandle.handlePivot.x < 80
            && raisedHandle.handlePivot.y < 170
            && raisedHandle.handleTip.y < raisedHandle.handlePivot.y
            && downwardStrike.handleTip.x > downwardStrike.handlePivot.x
            && downwardStrike.handleTip.y < downwardStrike.handlePivot.y
            && strikeAngle > -52
            && strikeAngle < -38
            && downwardLash.delta.x > 0
            && downwardLash.delta.y > 20

        didPass = didPass && maximumHandleError < 0.001 && maximumLashError < 0.95
        didPass = didPass && comesFromUpperLeft
        let output = ([
            String(
                format: "Whip physics: handle error %.4f px, max lash error %.3f px",
                Double(maximumHandleError),
                Double(maximumLashError)
            ),
            String(
                format: "direction: %.1f-degree raised handle, best lash delta (%.1f, %.1f) at %.2f %@",
                Double(strikeAngle),
                Double(downwardLash.delta.x),
                Double(downwardLash.delta.y),
                downwardLash.progress,
                comesFromUpperLeft ? "passed" : "failed"
            )
        ] + strikeDiagnostics).joined(separator: "\n") + "\n"

        if didPass {
            print(output, terminator: "")
        } else {
            FileHandle.standardError.write(Data(output.utf8))
            FileHandle.standardError.write(Data("Whip physics self-check failed\n".utf8))
        }
        return didPass
    }

    private static func peak(
        from start: TimeInterval,
        through end: TimeInterval
    ) -> (speed: CGFloat, time: TimeInterval) {
        var result = (speed: CGFloat.zero, time: start)
        for elapsed in stride(from: start, through: end, by: 1.0 / 240.0) {
            let speed = WhipPhysics.state(at: elapsed).tipSpeed
            if speed > result.speed {
                result = (speed, elapsed)
            }
        }
        return result
    }

    private static func peakCrack(from start: TimeInterval, through end: TimeInterval) -> Double {
        stride(from: start, through: end, by: 1.0 / 240.0)
            .map { WhipPhysics.state(at: $0).crackIntensity }
            .max() ?? 0
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
