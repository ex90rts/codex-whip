import CoreGraphics
import Foundation
import Testing
@testable import CodexWhip

struct WhipPhysicsTests {
    @Test func rigidHandleKeepsItsLength() {
        for elapsed in stride(from: 0.0, through: WhipPhysics.animationDuration, by: 0.04) {
            let state = WhipPhysics.state(at: elapsed)
            #expect(abs(distance(state.handlePivot, state.handleTip) - WhipPhysics.handleLength) < 0.001)
        }
    }

    @Test func flexibleLashKeepsItsSegmentLengths() {
        for elapsed in stride(from: 0.0, through: WhipPhysics.animationDuration, by: 0.04) {
            let state = WhipPhysics.state(at: elapsed)
            #expect(state.lashPoints.count == WhipPhysics.lashNodeCount)
            #expect(WhipPhysics.maximumSegmentError(in: state) < 0.95)
        }
    }

    @Test func eachStrikeAcceleratesTheTipAfterWindUp() {
        for strikeIndex in 0..<WhipPhysics.strikeCount {
            let cycleStart = Double(strikeIndex) * WhipPhysics.cycleDuration
            let windUpSpeed = maximumTipSpeed(
                from: cycleStart + 0.04,
                through: cycleStart + 0.17
            )
            let snapSpeed = maximumTipSpeed(
                from: cycleStart + 0.25,
                through: cycleStart + 0.48
            )

            #expect(snapSpeed > windUpSpeed * 1.35)
            #expect(snapSpeed > 550)
        }
    }

    @Test func handleStrikesDownwardFromTheUpperLeft() {
        let raisedHandle = WhipPhysics.state(at: WhipPhysics.cycleDuration * 0.38)
        let downwardStrike = WhipPhysics.state(at: WhipPhysics.cycleDuration * 0.56)
        let followThrough = WhipPhysics.state(at: WhipPhysics.cycleDuration * 0.84)
        let strikeAngle = atan2(
            downwardStrike.handleTip.y - downwardStrike.handlePivot.y,
            downwardStrike.handleTip.x - downwardStrike.handlePivot.x
        ) * 180 / .pi
        let lashTip = followThrough.lashPoints.last ?? followThrough.handleTip

        #expect(raisedHandle.handlePivot.x < 80)
        #expect(raisedHandle.handlePivot.y < 170)
        #expect(raisedHandle.handleTip.x > raisedHandle.handlePivot.x)
        #expect(raisedHandle.handleTip.y < raisedHandle.handlePivot.y)
        #expect(downwardStrike.handleTip.x > downwardStrike.handlePivot.x)
        #expect(downwardStrike.handleTip.y < downwardStrike.handlePivot.y)
        #expect(strikeAngle > -52)
        #expect(strikeAngle < -38)
        #expect(lashTip.x > followThrough.handleTip.x)
        #expect(lashTip.y > followThrough.handleTip.y + 20)
    }

    private func maximumTipSpeed(from start: TimeInterval, through end: TimeInterval) -> CGFloat {
        stride(from: start, through: end, by: 1.0 / 120.0)
            .map { WhipPhysics.state(at: $0).tipSpeed }
            .max() ?? 0
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
