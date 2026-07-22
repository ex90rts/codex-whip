import AppKit
import ApplicationServices

@MainActor
final class PetReactionController {
    private let hoverController = MouseHoverController()
    private var motionTask: Task<Void, Never>?

    func begin(
        _ kind: ReactionKind,
        at location: PetLocation,
        enablesHover: Bool
    ) {
        stop()

        if kind == .praise, enablesHover {
            // The cursor reaches the pet before the hand settles, giving the
            // native overlay a chance to run its own hover response.
            hoverController.beginHover(atAppKitPoint: location.interactionAnchor, duration: 0.95)
        }

        if kind == .whip {
            let firstImpactDelay = ReactionSoundFactory.whipCrackTime(strikeIndex: 0) + 0.015
            motionTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(firstImpactDelay * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.hoverController.beginNativeDragShake(atAppKitPoint: location.interactionAnchor)
            }
            let delayText = String(format: "%.3f", firstImpactDelay)
            writeDiagnostic(
                "[PET-FEEDBACK] native drag shake scheduled after first impact (+\(delayText)s)"
            )
            return
        }

        guard AXIsProcessTrusted() else {
            writeDiagnostic("[PET-FEEDBACK] begin \(kind) rejected: Accessibility is not trusted")
            return
        }
        guard let target = movableWindow(near: location) else {
            writeDiagnostic(diagnostic(near: location))
            return
        }
        let scoreText = String(format: "%.1f", target.score)
        writeDiagnostic(
            "[PET-FEEDBACK] begin \(kind) target=\(describe(target.frame)) score=\(scoreText)"
        )
        motionTask = Task { [weak self] in
            defer {
                let restored = self?.setPosition(target.originalPosition, of: target.element) ?? false
                self?.writeDiagnostic("[PET-FEEDBACK] restored=\(restored)")
            }

            let duration: TimeInterval = kind == .praise ? 0.72 : 0.70
            let frames = max(1, Int((duration * 60).rounded()))
            for frame in 0...frames {
                guard !Task.isCancelled else { return }
                let progress = Double(frame) / Double(frames)
                let offset = self?.offset(for: kind, progress: progress) ?? .zero
                guard self?.setPosition(
                    CGPoint(
                        x: target.originalPosition.x + offset.x,
                        y: target.originalPosition.y + offset.y
                    ),
                    of: target.element
                ) == true else {
                    self?.writeDiagnostic("[PET-FEEDBACK] move failed at frame \(frame)/\(frames)")
                    return
                }
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            self?.writeDiagnostic("[PET-FEEDBACK] applied \(frames + 1) position updates")
        }
    }

    func stop() {
        motionTask?.cancel()
        motionTask = nil
        hoverController.cancel()
    }

    func diagnostic(near location: PetLocation) -> String {
        guard AXIsProcessTrusted() else {
            return "[PET-FEEDBACK] Accessibility is not trusted"
        }
        guard let expectedFrame = ScreenCoordinateConverter.quartzRect(fromAppKitRect: location.frame) else {
            return "[PET-FEEDBACK] Could not convert the pet frame to Quartz coordinates"
        }

        let applications = matchingApplications()
        var lines = [
            "[PET-FEEDBACK] expected Quartz frame=\(describe(expectedFrame)) apps=\(applications.count)"
        ]
        var windowCount = 0
        for application in applications {
            for element in windows(in: application.processIdentifier) {
                windowCount += 1
                guard let frame = frame(of: element) else {
                    lines.append("[PET-FEEDBACK] pid=\(application.processIdentifier) AX window has no frame")
                    continue
                }
                let centerDistance = hypot(
                    frame.midX - expectedFrame.midX,
                    frame.midY - expectedFrame.midY
                )
                let sizeDistance = hypot(
                    frame.width - expectedFrame.width,
                    frame.height - expectedFrame.height
                )
                let score = centerDistance + sizeDistance * 0.4
                lines.append(
                    "[PET-FEEDBACK] pid=\(application.processIdentifier) frame=\(describe(frame)) settable=\(isPositionSettable(element)) score=\(String(format: "%.1f", score))"
                )
            }
        }
        lines.insert("[PET-FEEDBACK] AX top-level windows=\(windowCount)", at: 1)
        if let match = movableWindow(near: location) {
            lines.append("[PET-FEEDBACK] MATCH settable score=\(String(format: "%.1f", match.score))")
        } else {
            lines.append("[PET-FEEDBACK] MATCH none")
        }
        return lines.joined(separator: "\n")
    }

    private func offset(for kind: ReactionKind, progress: Double) -> CGPoint {
        switch kind {
        case .praise:
            // A small, slowing sway complements the native hover pose without
            // changing the pet's saved desktop position.
            let settle = pow(1 - progress, 1.4)
            return CGPoint(
                x: sin(progress * .pi * 3.2) * 5.5 * settle,
                y: -sin(progress * .pi) * 3.0 * settle
            )
        case .whip:
            let tremble = pow(1 - progress, 0.62)
            return CGPoint(
                x: sin(progress * .pi * 25) * 8.5 * tremble,
                y: sin(progress * .pi * 17 + 0.4) * 3.6 * tremble
            )
        }
    }

    private func movableWindow(near location: PetLocation) -> MovableWindow? {
        guard AXIsProcessTrusted(),
              let expectedFrame = ScreenCoordinateConverter.quartzRect(fromAppKitRect: location.frame) else {
            return nil
        }

        let applications = matchingApplications()

        var candidateWindows: [AXUIElement] = []
        for application in applications {
            candidateWindows.append(contentsOf: windows(in: application.processIdentifier))
        }

        return candidateWindows
            .compactMap { element -> MovableWindow? in
                guard let frame = frame(of: element),
                      isPositionSettable(element),
                      let position = position(of: element) else {
                    return nil
                }

                let centerDistance = hypot(
                    frame.midX - expectedFrame.midX,
                    frame.midY - expectedFrame.midY
                )
                let sizeDistance = hypot(
                    frame.width - expectedFrame.width,
                    frame.height - expectedFrame.height
                )
                let score = centerDistance + sizeDistance * 0.4
                guard score < 96 else { return nil }
                return MovableWindow(
                    element: element,
                    originalPosition: position,
                    score: score,
                    frame: frame
                )
            }
            .min(by: { $0.score < $1.score })
    }

    private func windows(in processIdentifier: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func matchingApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            let identity = "\(application.localizedName ?? "") \(application.bundleIdentifier ?? "")"
                .lowercased()
            return application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && ["codex", "openai", "chatgpt"].contains(where: identity.contains)
        }
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = position(of: element), let size = size(of: element) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func position(of element: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = attributeValue(kAXPositionAttribute, of: element),
              AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func isPositionSettable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(
            element,
            kAXPositionAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    private func size(of element: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard let value = attributeValue(kAXSizeAttribute, of: element),
              AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func attributeValue(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value as! AXValue? else {
            return nil
        }
        return axValue
    }

    @discardableResult
    private func setPosition(_ point: CGPoint, of element: AXUIElement) -> Bool {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            value
        ) == .success
    }

    private func describe(_ frame: CGRect) -> String {
        "(\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))×\(Int(frame.height)))"
    }

    private func writeDiagnostic(_ message: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-whip-feedback.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try? "\(timestamp) \(message)\n".write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct MovableWindow {
    let element: AXUIElement
    let originalPosition: CGPoint
    let score: CGFloat
    let frame: CGRect
}
