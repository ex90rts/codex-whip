import CoreGraphics
import Testing
@testable import CodexWhip

struct PetLocatorPipelineTests {
    @Test func acceptsLiveCodexPetOverlayGeometry() {
        let score = PetOverlayWindowScorer.confidence(for: WindowDescriptor(
            id: 23_714,
            quartzFrame: CGRect(x: 2_266, y: 1_091, width: 243, height: 253),
            layer: 2,
            alpha: 1,
            name: ""
        ))

        #expect(score >= PetLocation.minimumConfidence)
    }

    @Test func rejectsLiveCodexToolbarGeometry() {
        let score = PetOverlayWindowScorer.confidence(for: WindowDescriptor(
            id: 23_715,
            quartzFrame: CGRect(x: 2_203, y: 1_090, width: 345, height: 54),
            layer: 3,
            alpha: 1,
            name: ""
        ))

        #expect(score < PetLocation.minimumConfidence)
    }

    @Test func usesFirstConfidentAutomaticLocation() async {
        let expected = PetLocation(
            frame: CGRect(x: 100, y: 200, width: 96, height: 112),
            confidence: 0.91,
            source: .accessibility,
            detail: "test"
        )
        let pipeline = PetLocatorPipeline(locators: [
            StubPetLocator(result: nil),
            StubPetLocator(result: expected),
            StubPetLocator(result: PetLocation(
                frame: CGRect(x: 900, y: 900, width: 10, height: 10),
                confidence: 1,
                source: .electronState,
                detail: "must not run"
            ))
        ])

        let result = await pipeline.locatePet()

        #expect(result == expected)
    }

    @Test func rejectsLowConfidenceCandidateAndContinues() async {
        let expected = PetLocation(
            frame: CGRect(x: 300, y: 400, width: 80, height: 90),
            confidence: 0.88,
            source: .electronState,
            detail: "test"
        )
        let pipeline = PetLocatorPipeline(locators: [
            StubPetLocator(result: PetLocation(
                frame: CGRect(x: 10, y: 10, width: 30, height: 30),
                confidence: 0.42,
                source: .window,
                detail: "weak"
            )),
            StubPetLocator(result: expected)
        ])

        let result = await pipeline.locatePet()

        #expect(result == expected)
    }

    @Test func doesNotInventMouseLocationWhenEveryLocatorFails() async {
        let pipeline = PetLocatorPipeline(locators: [StubPetLocator(result: nil)])
        #expect(await pipeline.locatePet() == nil)
    }
}

private struct StubPetLocator: PetLocating {
    let result: PetLocation?

    func locatePet() async -> PetLocation? {
        result
    }
}
