import AppKit
import Foundation

/// Last-resort, permission-free lookup for the bounds persisted by Codex's
/// Electron avatar overlay. WindowServer and Accessibility remain preferable
/// because persisted state can be stale while the pet is being dragged.
struct ElectronSavedBoundsPetLocator: PetLocating {
    static let boundsKey = "electron-avatar-overlay-bounds"

    private let preferenceDomains = [
        "com.openai.codex",
        "com.openai.chatgpt",
        "openai.chatgpt"
    ]

    func locatePet() async -> PetLocation? {
        for domain in preferenceDomains {
            guard let preferences = UserDefaults.standard.persistentDomain(forName: domain),
                  let value = Self.findBoundsValue(in: preferences),
                  let location = Self.location(from: value, detail: "Electron preferences: \(domain)") else {
                continue
            }
            return location
        }

        for url in candidateJSONFiles() {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let value = Self.findBoundsValue(in: object),
                  let location = Self.location(from: value, detail: "Electron state: \(url.lastPathComponent)") else {
                continue
            }
            return location
        }
        return nil
    }

    private func candidateJSONFiles() -> [URL] {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let roots = ["Codex", "ChatGPT"]
        let fileNames = [
            "Preferences",
            "window-state.json",
            "window-state-main.json",
            "config.json"
        ]

        return roots.flatMap { root in
            fileNames.compactMap { name in
                applicationSupport?.appendingPathComponent(root).appendingPathComponent(name)
            }
        }
    }

    static func findBoundsValue(in object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            if let exact = dictionary[boundsKey] {
                return exact
            }
            for value in dictionary.values {
                if let match = findBoundsValue(in: value) { return match }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findBoundsValue(in: value) { return match }
            }
        } else if let string = object as? String,
                  let data = string.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) {
            return findBoundsValue(in: decoded)
        }
        return nil
    }

    static func location(from value: Any, detail: String) -> PetLocation? {
        guard let geometry = persistedGeometry(from: value) else {
            return nil
        }

        let geometryConfidence: Double
        if geometry.isMascotFrame {
            geometryConfidence = 0.70
        } else {
            let descriptor = WindowDescriptor(
                id: 0,
                quartzFrame: geometry.quartzFrame,
                layer: 0,
                alpha: 1,
                name: "avatar"
            )
            geometryConfidence = PetOverlayWindowScorer.confidence(for: descriptor)
            guard geometryConfidence >= PetLocation.minimumConfidence else {
                return nil
            }
        }

        guard let appKitFrame = ScreenCoordinateConverter.appKitRect(
            fromQuartzRect: geometry.quartzFrame
        ) else {
            return nil
        }

        return PetLocation(
            frame: appKitFrame,
            confidence: min(geometryConfidence, 0.70),
            source: .electronState,
            detail: detail
        )
    }

    static func persistedGeometry(from value: Any) -> PersistedPetGeometry? {
        let decodedValue: Any
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            decodedValue = decoded
        } else {
            decodedValue = value
        }

        guard let dictionary = decodedValue as? [String: Any],
              let x = number(named: "x", in: dictionary),
              let y = number(named: "y", in: dictionary) else {
            return nil
        }

        let width = number(named: "width", in: dictionary)
        let height = number(named: "height", in: dictionary)
        if width == nil && height == nil {
            return PersistedPetGeometry(
                quartzFrame: CGRect(
                    origin: CGPoint(x: x, y: y),
                    size: PetOverlayGeometry.defaultMascotSize
                ),
                isMascotFrame: true
            )
        }

        guard let width, let height, width > 0, height > 0 else {
            return nil
        }

        return PersistedPetGeometry(
            quartzFrame: CGRect(x: x, y: y, width: width, height: height),
            isMascotFrame: false
        )
    }

    private static func number(named key: String, in dictionary: [String: Any]) -> Double? {
        if let number = dictionary[key] as? NSNumber { return number.doubleValue }
        if let string = dictionary[key] as? String { return Double(string) }
        return nil
    }
}

struct PersistedPetGeometry: Equatable, Sendable {
    let quartzFrame: CGRect
    let isMascotFrame: Bool
}
