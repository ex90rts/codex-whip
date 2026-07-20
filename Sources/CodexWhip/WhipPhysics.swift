import CoreGraphics
import Foundation

struct WhipPhysicsState {
    let handlePivot: CGPoint
    let handleTip: CGPoint
    let lashPoints: [CGPoint]
    let tipSpeed: CGFloat
    let crackIntensity: Double
}

enum WhipPhysics {
    static let strikeCount = 3
    static let cycleDuration: TimeInterval = 0.62
    static let animationDuration = cycleDuration * Double(strikeCount)
    static let handleLength: CGFloat = 62
    static let lashSegmentLength: CGFloat = 7.2
    static let lashNodeCount = 23

    private static let simulationStep: TimeInterval = 1.0 / 180.0
    private static let handleVerticalOffset = handleLength * 0.30 + 50
    private static let restingHandlePivot = CGPoint(x: 34, y: 70 + handleVerticalOffset)
    private static let raisedHandlePivot = CGPoint(x: 30, y: 58 + handleVerticalOffset)
    private static let strikingHandlePivot = CGPoint(x: 43, y: 78 + handleVerticalOffset)

    static func state(at elapsed: TimeInterval) -> WhipPhysicsState {
        let clampedElapsed = min(max(elapsed, 0), animationDuration)
        var simulation = Simulation()
        let stepCount = Int(ceil(clampedElapsed / simulationStep))

        if stepCount > 0 {
            for step in 1...stepCount {
                simulation.advance(to: Double(step) * simulationStep)
            }
        }

        let tipVelocity = simulation.tipVelocity
        let tipSpeed = magnitude(tipVelocity)
        let localProgress = strikeProgress(at: clampedElapsed)
        let strikeWindow = gaussian(value: localProgress, center: 0.64, width: 0.16)
        let speedEnergy = smoothStep(
            min(max((Double(tipSpeed) - 430) / 1_050, 0), 1)
        )

        return WhipPhysicsState(
            handlePivot: simulation.handlePivot,
            handleTip: simulation.handleTip,
            lashPoints: simulation.points,
            tipSpeed: tipSpeed,
            crackIntensity: speedEnergy * strikeWindow
        )
    }

    static func maximumSegmentError(in state: WhipPhysicsState) -> CGFloat {
        zip(state.lashPoints, state.lashPoints.dropFirst())
            .map { abs(distance($0, $1) - lashSegmentLength) }
            .max() ?? 0
    }

    private static func strikeProgress(at elapsed: TimeInterval) -> Double {
        guard elapsed < animationDuration else { return 1 }
        return (elapsed / cycleDuration).truncatingRemainder(dividingBy: 1)
    }

    private struct HandlePose {
        let pivot: CGPoint
        let angle: CGFloat
    }

    private static func handlePose(at elapsed: TimeInterval) -> HandlePose {
        let boundedTime = min(max(elapsed, 0), animationDuration - simulationStep * 0.5)
        let strikeIndex = min(Int(boundedTime / cycleDuration), strikeCount - 1)
        let local = (boundedTime / cycleDuration).truncatingRemainder(dividingBy: 1)
        let variation: [CGFloat] = [-0.025, 0.035, -0.015]
        let bias = variation[strikeIndex]
        let ready = CGFloat(-0.68) + bias
        let windUp = CGFloat(-1.48) + bias
        // Keep the rigid handle at roughly 45 degrees during impact. The lash
        // remains free to continue downward after the handle changes direction.
        let strike = -CGFloat.pi / 4 + bias

        switch local {
        case ..<0.16:
            return HandlePose(pivot: restingHandlePivot, angle: ready)
        case ..<0.42:
            let progress = smootherStep((local - 0.16) / 0.26)
            return HandlePose(
                pivot: interpolate(restingHandlePivot, raisedHandlePivot, progress),
                angle: interpolate(ready, windUp, progress)
            )
        case ..<0.56:
            let progress = smootherStep((local - 0.42) / 0.14)
            return HandlePose(
                pivot: interpolate(raisedHandlePivot, strikingHandlePivot, progress),
                angle: interpolate(windUp, strike, progress)
            )
        case ..<0.64:
            return HandlePose(pivot: strikingHandlePivot, angle: strike)
        case ..<0.86:
            let progress = smootherStep((local - 0.64) / 0.22)
            return HandlePose(
                pivot: interpolate(strikingHandlePivot, restingHandlePivot, progress),
                angle: interpolate(strike, ready, progress)
            )
        default:
            return HandlePose(pivot: restingHandlePivot, angle: ready)
        }
    }

    private struct Simulation {
        var points: [CGPoint]
        var previousPoints: [CGPoint]
        var handlePivot: CGPoint
        var handleTip: CGPoint
        var tipVelocity = CGPoint.zero

        init() {
            let initialPose = WhipPhysics.handlePose(at: 0)
            let initialAngle = initialPose.angle
            let direction = unitVector(angle: initialAngle)
            handlePivot = initialPose.pivot
            handleTip = add(
                handlePivot,
                scaled(direction, by: WhipPhysics.handleLength)
            )

            var lashPoints = [handleTip]
            lashPoints.reserveCapacity(WhipPhysics.lashNodeCount)
            var cursor = handleTip

            for index in 1..<WhipPhysics.lashNodeCount {
                let progress = CGFloat(index) / CGFloat(WhipPhysics.lashNodeCount - 1)
                let hangingProgress = smootherStep(min(Double(progress / 0.58), 1))
                let hangingDirection = CGFloat(0.68)
                let relaxedCurve = interpolate(
                    initialAngle,
                    hangingDirection,
                    hangingProgress
                ) + 0.10 * sin(progress * .pi)
                cursor = add(
                    cursor,
                    scaled(unitVector(angle: relaxedCurve), by: WhipPhysics.lashSegmentLength)
                )
                lashPoints.append(cursor)
            }

            points = lashPoints
            previousPoints = lashPoints
        }

        mutating func advance(to elapsed: TimeInterval) {
            let pose = WhipPhysics.handlePose(at: elapsed)
            let direction = unitVector(angle: pose.angle)
            let nextHandleTip = add(
                pose.pivot,
                scaled(direction, by: WhipPhysics.handleLength)
            )
            let previousTip = points[points.count - 1]
            let timeSquared = CGFloat(WhipPhysics.simulationStep * WhipPhysics.simulationStep)

            for index in 1..<points.count {
                let current = points[index]
                let velocity = scaled(
                    subtract(current, previousPoints[index]),
                    by: 0.992
                )
                previousPoints[index] = current
                points[index] = add(
                    add(current, velocity),
                    CGPoint(x: 0, y: 165 * timeSquared)
                )
            }

            previousPoints[0] = points[0]
            points[0] = nextHandleTip
            solveConstraints(handleDirection: direction, pinnedPoint: nextHandleTip)
            handlePivot = pose.pivot
            handleTip = nextHandleTip
            tipVelocity = scaled(
                subtract(points[points.count - 1], previousTip),
                by: CGFloat(1 / WhipPhysics.simulationStep)
            )
        }

        private mutating func solveConstraints(
            handleDirection: CGPoint,
            pinnedPoint: CGPoint
        ) {
            let segmentLength = WhipPhysics.lashSegmentLength

            for _ in 0..<28 {
                points[0] = pinnedPoint

                // The first few centimetres of a real whip are thicker and resist
                // bending. This soft guide couples them to the rigid handle while
                // leaving the rest of the lash unconstrained and flexible.
                let firstTarget = add(pinnedPoint, scaled(handleDirection, by: segmentLength))
                points[1] = interpolate(points[1], firstTarget, 0.038)
                let secondTarget = add(firstTarget, scaled(handleDirection, by: segmentLength))
                points[2] = interpolate(points[2], secondTarget, 0.012)

                for index in 0..<(points.count - 1) {
                    let delta = subtract(points[index + 1], points[index])
                    let currentLength = max(magnitude(delta), 0.0001)
                    let correction = scaled(
                        delta,
                        by: (currentLength - segmentLength) / currentLength
                    )

                    if index == 0 {
                        points[index + 1] = subtract(points[index + 1], correction)
                    } else {
                        let leadingWeight = inverseMass(at: index)
                        let trailingWeight = inverseMass(at: index + 1)
                        let totalWeight = leadingWeight + trailingWeight
                        points[index] = add(
                            points[index],
                            scaled(correction, by: leadingWeight / totalWeight)
                        )
                        points[index + 1] = subtract(
                            points[index + 1],
                            scaled(correction, by: trailingWeight / totalWeight)
                        )
                    }
                }
            }

            points[0] = pinnedPoint
        }

        private func inverseMass(at index: Int) -> CGFloat {
            let progress = CGFloat(index) / CGFloat(points.count - 1)
            return 1 + 5 * pow(progress, 1.45)
        }
    }

    private static func gaussian(value: Double, center: Double, width: Double) -> Double {
        exp(-pow((value - center) / width, 2))
    }

    private static func smootherStep(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10))
    }

    private static func smoothStep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private static func interpolate(_ start: CGPoint, _ end: CGPoint, _ progress: CGFloat) -> CGPoint {
        CGPoint(
            x: interpolate(start.x, end.x, progress),
            y: interpolate(start.y, end.y, progress)
        )
    }

    private static func unitVector(angle: CGFloat) -> CGPoint {
        CGPoint(x: cos(angle), y: sin(angle))
    }

    private static func add(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    private static func subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    private static func scaled(_ point: CGPoint, by scalar: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scalar, y: point.y * scalar)
    }

    private static func magnitude(_ point: CGPoint) -> CGFloat {
        hypot(point.x, point.y)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        magnitude(subtract(lhs, rhs))
    }
}
