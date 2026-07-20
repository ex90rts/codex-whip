import AppKit
import ApplicationServices

struct AccessibilityPetLocator: PetLocating {
    private let applicationTokens = ["codex", "openai", "chatgpt"]
    private let petTokens = ["pet", "avatar", "companion", "mascot", "宠物"]

    func locatePet() async -> PetLocation? {
        guard AXIsProcessTrusted() else { return nil }

        for application in matchingApplications() {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            if let window = bestTopLevelWindow(in: root) {
                return window
            }
            if let result = search(root: root) {
                return result
            }
        }
        return nil
    }

    private func bestTopLevelWindow(in application: AXUIElement) -> PetLocation? {
        arrayAttribute(kAXWindowsAttribute, of: application)
            .compactMap { element -> PetLocation? in
                guard let quartzFrame = frame(of: element) else { return nil }
                let text = descriptiveText(for: element)
                let descriptor = WindowDescriptor(
                    id: 0,
                    quartzFrame: quartzFrame,
                    layer: 0,
                    alpha: 1,
                    name: text
                )
                let confidence = PetOverlayWindowScorer.confidence(for: descriptor)
                guard confidence >= PetLocation.minimumConfidence,
                      let appKitFrame = ScreenCoordinateConverter.appKitRect(fromQuartzRect: quartzFrame) else {
                    return nil
                }
                return PetLocation(
                    frame: appKitFrame,
                    confidence: confidence,
                    source: .accessibility,
                    detail: text.isEmpty
                        ? "Accessibility top-level window, \(Int(quartzFrame.width))×\(Int(quartzFrame.height))"
                        : text
                )
            }
            .max(by: { $0.confidence < $1.confidence })
    }

    private func matchingApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            let identity = "\(application.localizedName ?? "") \(application.bundleIdentifier ?? "")".lowercased()
            return application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && applicationTokens.contains(where: identity.contains)
        }
    }

    private func search(root: AXUIElement) -> PetLocation? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0

        while !queue.isEmpty && visited < 4_000 {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if let candidate = candidate(for: element) {
                return candidate
            }

            guard depth < 9 else { continue }
            for child in arrayAttribute(kAXChildrenAttribute, of: element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private func candidate(for element: AXUIElement) -> PetLocation? {
        let role = stringAttribute(kAXRoleAttribute, of: element).lowercased()
        let text = descriptiveText(for: element).lowercased()

        let isVisualRole = role == kAXImageRole.lowercased()
            || role == kAXGroupRole.lowercased()
            || role.contains("canvas")
        guard isVisualRole, petTokens.contains(where: text.contains),
              let quartzFrame = frame(of: element),
              quartzFrame.width >= 30, quartzFrame.height >= 30,
              quartzFrame.width <= 520, quartzFrame.height <= 520,
              let appKitFrame = ScreenCoordinateConverter.appKitRect(fromQuartzRect: quartzFrame) else {
            return nil
        }

        return PetLocation(
            frame: appKitFrame,
            confidence: 0.94,
            source: .accessibility,
            detail: text.isEmpty ? role : text
        )
    }

    private func descriptiveText(for element: AXUIElement) -> String {
        [
            stringAttribute(kAXTitleAttribute, of: element),
            stringAttribute(kAXDescriptionAttribute, of: element),
            stringAttribute(kAXHelpAttribute, of: element)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = valueAttribute(kAXPositionAttribute, of: element),
              let sizeValue = valueAttribute(kAXSizeAttribute, of: element) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private func valueAttribute(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as! AXValue?
    }

    private func arrayAttribute(_ attribute: String, of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }
}
