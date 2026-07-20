import AppKit
import CoreGraphics

struct WindowPetLocator: PetLocating {
    private let ownerTokens = ["codex", "openai", "chatgpt"]

    func locatePet() async -> PetLocation? {
        let ownerPIDs = matchingApplicationPIDs()
        guard !ownerPIDs.isEmpty,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        return windowInfo
            .compactMap { descriptor(from: $0, ownerPIDs: ownerPIDs) }
            .compactMap(candidate(for:))
            .max(by: { $0.confidence < $1.confidence })
    }

    private func matchingApplicationPIDs() -> Set<pid_t> {
        Set(NSWorkspace.shared.runningApplications.compactMap { application in
            let identity = "\(application.localizedName ?? "") \(application.bundleIdentifier ?? "")".lowercased()
            guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  ownerTokens.contains(where: identity.contains) else {
                return nil
            }
            return application.processIdentifier
        })
    }

    private func descriptor(
        from dictionary: [String: Any],
        ownerPIDs: Set<pid_t>
    ) -> WindowDescriptor? {
        guard let ownerPID = number(kCGWindowOwnerPID, in: dictionary),
              ownerPIDs.contains(pid_t(ownerPID.int32Value)),
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        return WindowDescriptor(
            id: CGWindowID(number(kCGWindowNumber, in: dictionary)?.uint32Value ?? 0),
            quartzFrame: bounds,
            layer: number(kCGWindowLayer, in: dictionary)?.intValue ?? 0,
            alpha: number(kCGWindowAlpha, in: dictionary)?.doubleValue ?? 1,
            name: (dictionary[kCGWindowName as String] as? String) ?? ""
        )
    }

    private func candidate(for window: WindowDescriptor) -> PetLocation? {
        let score = PetOverlayWindowScorer.confidence(for: window)
        guard score >= PetLocation.minimumConfidence,
              let appKitFrame = ScreenCoordinateConverter.appKitRect(fromQuartzRect: window.quartzFrame) else {
            return nil
        }

        return PetLocation(
            frame: appKitFrame,
            confidence: score,
            source: .window,
            detail: "WindowServer window #\(window.id), \(Int(window.quartzFrame.width))×\(Int(window.quartzFrame.height))"
        )
    }

    private func number(_ key: CFString, in dictionary: [String: Any]) -> NSNumber? {
        dictionary[key as String] as? NSNumber
    }
}

struct WindowDescriptor: Sendable {
    let id: CGWindowID
    let quartzFrame: CGRect
    let layer: Int
    let alpha: Double
    let name: String
}

enum PetOverlayWindowScorer {
    // Codex has shipped more than one avatar-overlay geometry. Keep the
    // observed sizes together so version changes do not leak into callers.
    private static let knownSizes = [
        CGSize(width: 356, height: 320),
        CGSize(width: 243, height: 253)
    ]

    static func confidence(for window: WindowDescriptor) -> Double {
        let sizeDifference = knownSizes
            .map { size in
                (
                    width: abs(window.quartzFrame.width - size.width),
                    height: abs(window.quartzFrame.height - size.height)
                )
            }
            .min { lhs, rhs in
                max(lhs.width, lhs.height) < max(rhs.width, rhs.height)
            } ?? (width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let name = window.name.lowercased()
        let nameIdentifiesPet = ["pet", "avatar", "mascot", "companion", "宠物"]
            .contains(where: name.contains)

        var confidence: Double
        if sizeDifference.width <= 8 && sizeDifference.height <= 8 {
            confidence = 0.93
        } else if sizeDifference.width <= 40 && sizeDifference.height <= 40 {
            confidence = 0.78
        } else {
            let aspectRatio = window.quartzFrame.width / window.quartzFrame.height
            let isPlausibleOverlay = window.quartzFrame.width >= 180
                && window.quartzFrame.width <= 480
                && window.quartzFrame.height >= 180
                && window.quartzFrame.height <= 440
                && aspectRatio >= 0.72
                && aspectRatio <= 1.35
                && window.layer > 0
            confidence = isPlausibleOverlay ? 0.64 : 0
        }

        if nameIdentifiesPet { confidence += 0.08 }
        if window.layer > 0 { confidence += 0.03 }
        if window.alpha < 0.999 { confidence += 0.03 }
        return min(confidence, 0.99)
    }
}
