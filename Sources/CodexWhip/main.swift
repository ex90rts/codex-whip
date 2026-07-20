import AppKit

@main
enum CodexWhipApplication {
    @MainActor
    static func main() {
        let previewSoundKind: ReactionKind? = CommandLine.arguments.contains("--preview-praise-sound")
            ? .praise
            : CommandLine.arguments.contains("--preview-whip-sound") ? .whip : nil
        if let previewSoundKind {
            let soundPlayer = ReactionSoundPlayer()
            soundPlayer.play(previewSoundKind)
            Task {
                let duration = previewSoundKind == .praise ? 1.8 : 2.3
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                _ = soundPlayer
                Darwin.exit(0)
            }
            dispatchMain()
        }

        if CommandLine.arguments.contains("--diagnose-pet") {
            Task.detached {
                let foundPet = await PetWindowDiagnostics.run()
                Darwin.exit(foundPet ? 0 : 1)
            }
            dispatchMain()
        }

        if CommandLine.arguments.contains("--diagnose-pet-feedback") {
            let feedbackController = PetReactionController()
            let locatorPipeline = PetLocatorPipeline(locators: [
                WindowPetLocator(),
                AccessibilityPetLocator(),
                ElectronSavedBoundsPetLocator()
            ])
            Task {
                if let location = await locatorPipeline.locatePet() {
                    print(feedbackController.diagnostic(near: location))
                    Darwin.exit(0)
                }
                FileHandle.standardError.write(Data("[PET-FEEDBACK] Pet not found\n".utf8))
                Darwin.exit(1)
            }
            dispatchMain()
        }

        if CommandLine.arguments.contains("--self-check") {
            Task.detached {
                let petLocatorSucceeded = await PetLocatorSelfCheck.run()
                let whipPhysicsSucceeded = WhipPhysicsSelfCheck.run()
                let reactionSoundSucceeded = ReactionSoundSelfCheck.run()
                Darwin.exit(
                    petLocatorSucceeded && whipPhysicsSucceeded && reactionSoundSucceeded ? 0 : 1
                )
            }
            dispatchMain()
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
