import CoreGraphics
import Foundation

enum PetLocationSource: String, Codable, Sendable {
    case window
    case accessibility
    case electronState
}

struct PetLocation: Equatable, Sendable {
    static let minimumConfidence = 0.60

    let frame: CGRect
    let confidence: Double
    let source: PetLocationSource
    let detail: String

    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    var interactionAnchor: CGPoint {
        PetOverlayGeometry.interactionAnchor(for: self)
    }

    var isConfident: Bool {
        confidence >= Self.minimumConfidence && frame.width > 0 && frame.height > 0
    }
}

protocol PetLocating: Sendable {
    func locatePet() async -> PetLocation?
}

enum PetOverlayGeometry {
    static let defaultMascotSize = CGSize(width: 112, height: 121)

    private static let legacyOverlaySize = CGSize(width: 356, height: 320)
    private static let legacyMascotFrame = CGRect(
        origin: CGPoint(x: 216, y: 191),
        size: defaultMascotSize
    )
    private static let sizeTolerance: CGFloat = 8

    static func interactionAnchor(for location: PetLocation) -> CGPoint {
        guard matchesLegacyOverlay(location.frame) else {
            return location.center
        }

        // Codex's legacy renderer positions the mascot at this frame inside
        // its 356x320 transparent viewport. Its coordinates use a top-left
        // origin, while PetLocation uses AppKit's bottom-left origin.
        let scaleX = location.frame.width / legacyOverlaySize.width
        let scaleY = location.frame.height / legacyOverlaySize.height
        return CGPoint(
            x: location.frame.minX + legacyMascotFrame.midX * scaleX,
            y: location.frame.maxY - legacyMascotFrame.midY * scaleY
        )
    }

    private static func matchesLegacyOverlay(_ frame: CGRect) -> Bool {
        abs(frame.width - legacyOverlaySize.width) <= sizeTolerance
            && abs(frame.height - legacyOverlaySize.height) <= sizeTolerance
    }
}

struct PetLocatorPipeline: Sendable {
    private let locators: [any PetLocating]

    init(locators: [any PetLocating]) {
        self.locators = locators
    }

    func locatePet() async -> PetLocation? {
        for locator in locators {
            guard let candidate = await locator.locatePet(), candidate.isConfident else {
                continue
            }
            return candidate
        }
        return nil
    }
}
