import CoreGraphics
import Foundation

enum PetLocatorSelfCheck {
    static func run() async -> Bool {
        let automatic = PetLocation(
            frame: CGRect(x: 100, y: 200, width: 90, height: 100),
            confidence: 0.92,
            source: .electronState,
            detail: "self-check"
        )
        let lowConfidence = PetLocation(
            frame: CGRect(x: 999, y: 999, width: 30, height: 30),
            confidence: 0.20,
            source: .window,
            detail: "weak"
        )

        let selectsAutomatic = await PetLocatorPipeline(locators: [
            SelfCheckLocator(result: lowConfidence),
            SelfCheckLocator(result: automatic)
        ]).locatePet() == automatic

        let doesNotInventMousePosition = await PetLocatorPipeline(locators: [
            SelfCheckLocator(result: nil)
        ]).locatePet() == nil

        let exactOverlayScore = PetOverlayWindowScorer.confidence(for: WindowDescriptor(
            id: 1,
            quartzFrame: CGRect(x: 10, y: 20, width: 356, height: 320),
            layer: 1,
            alpha: 1,
            name: ""
        ))
        let mainWindowScore = PetOverlayWindowScorer.confidence(for: WindowDescriptor(
            id: 2,
            quartzFrame: CGRect(x: 10, y: 20, width: 1200, height: 900),
            layer: 0,
            alpha: 1,
            name: "Codex"
        ))
        let livePetWindowScore = PetOverlayWindowScorer.confidence(for: WindowDescriptor(
            id: 23_714,
            quartzFrame: CGRect(x: 2_266, y: 1_091, width: 243, height: 253),
            layer: 2,
            alpha: 1,
            name: ""
        ))
        let codexToolbarScore = PetOverlayWindowScorer.confidence(for: WindowDescriptor(
            id: 23_715,
            quartzFrame: CGRect(x: 2_203, y: 1_090, width: 345, height: 54),
            layer: 3,
            alpha: 1,
            name: ""
        ))

        guard selectsAutomatic,
              doesNotInventMousePosition,
              exactOverlayScore >= PetLocation.minimumConfidence,
              livePetWindowScore >= PetLocation.minimumConfidence,
              codexToolbarScore < PetLocation.minimumConfidence,
              mainWindowScore < PetLocation.minimumConfidence else {
            FileHandle.standardError.write(Data("Pet locator self-check failed\n".utf8))
            return false
        }

        print("Pet locator self-check passed: overlay geometry selected; main window rejected; no mouse fallback")
        return true
    }
}

private struct SelfCheckLocator: PetLocating {
    let result: PetLocation?

    func locatePet() async -> PetLocation? {
        result
    }
}
