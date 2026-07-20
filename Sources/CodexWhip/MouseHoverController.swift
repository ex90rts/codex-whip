import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class MouseHoverController {
    private var hoverTask: Task<Void, Never>?
    private var dragShakeTask: Task<Void, Never>?

    func beginHover(atAppKitPoint target: CGPoint, duration: TimeInterval) {
        cancel()

        // Permission checks must stay silent during playback. If Accessibility
        // is unavailable, the optional Hover effect is skipped.
        guard AXIsProcessTrusted() else { return }
        guard let targetQuartzPoint = ScreenCoordinateConverter.quartzPoint(fromAppKitPoint: target) else {
            return
        }

        let originalQuartzPoint = CGEvent(source: nil)?.location
        moveCursor(to: targetQuartzPoint)

        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self, let originalQuartzPoint else { return }

            let current = CGEvent(source: nil)?.location ?? targetQuartzPoint
            let userHasTakenControl = hypot(
                current.x - targetQuartzPoint.x,
                current.y - targetQuartzPoint.y
            ) > 24

            if !userHasTakenControl {
                self.moveCursor(to: originalQuartzPoint)
            }
        }
    }

    func cancel() {
        hoverTask?.cancel()
        hoverTask = nil
        dragShakeTask?.cancel()
        dragShakeTask = nil
    }

    func beginNativeDragShake(atAppKitPoint target: CGPoint, duration: TimeInterval = 0.70) {
        cancel()

        // The pet's own renderer turns a real pointer drag into a native
        // window move. Returning the pointer to its grab point before release
        // makes the pet end exactly where it started, without relying on an
        // AX write that Electron can silently ignore.
        guard AXIsProcessTrusted(),
              let targetQuartzPoint = ScreenCoordinateConverter.quartzPoint(fromAppKitPoint: target) else {
            return
        }

        let originalQuartzPoint = CGEvent(source: nil)?.location
        moveCursor(to: targetQuartzPoint)
        postMouse(.leftMouseDown, at: targetQuartzPoint)

        dragShakeTask = Task { [weak self] in
            let shakeFrames = max(12, Int(((duration - 0.08) * 60).rounded()))
            let settleFrames = 5
            let totalFrames = shakeFrames + settleFrames

            for frame in 0..<totalFrames {
                guard !Task.isCancelled, let self else { return }

                let point: CGPoint
                if frame < shakeFrames {
                    let progress = Double(frame) / Double(max(1, shakeFrames - 1))
                    let envelope = sin(progress * .pi)
                    point = CGPoint(
                        x: targetQuartzPoint.x + sin(progress * .pi * 16) * 11 * envelope,
                        y: targetQuartzPoint.y + sin(progress * .pi * 21 + 0.45) * 4.5 * envelope
                    )
                } else {
                    // A brief stationary tail removes release velocity, so the
                    // pet's own drag physics cannot carry it away afterward.
                    point = targetQuartzPoint
                }

                self.moveCursor(to: point)
                self.postMouse(.leftMouseDragged, at: point)
                try? await Task.sleep(nanoseconds: 16_666_667)
            }

            guard !Task.isCancelled, let self else { return }
            self.moveCursor(to: targetQuartzPoint)
            self.postMouse(.leftMouseDragged, at: targetQuartzPoint)
            self.postMouse(.leftMouseUp, at: targetQuartzPoint)

            guard let originalQuartzPoint else { return }
            try? await Task.sleep(nanoseconds: 80_000_000)
            let current = CGEvent(source: nil)?.location ?? targetQuartzPoint
            let userHasTakenControl = hypot(
                current.x - targetQuartzPoint.x,
                current.y - targetQuartzPoint.y
            ) > 24
            if !userHasTakenControl {
                self.moveCursor(to: originalQuartzPoint)
            }
        }
    }

    private func moveCursor(to point: CGPoint) {
        // Electron's native overlay listens to the real cursor location. A
        // posted event alone can be filtered as synthetic, so warp first and
        // then send a mouse-moved event to refresh its monitor.
        _ = CGWarpMouseCursorPosition(point)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }
}
