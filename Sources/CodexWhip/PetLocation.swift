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

    var isConfident: Bool {
        confidence >= Self.minimumConfidence && frame.width > 0 && frame.height > 0
    }
}

protocol PetLocating: Sendable {
    func locatePet() async -> PetLocation?
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
