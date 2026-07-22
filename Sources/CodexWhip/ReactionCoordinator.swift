import AppKit
import SwiftUI

enum ReactionKind {
    case praise
    case whip

    var duration: TimeInterval {
        switch self {
        case .praise: return 2.4
        case .whip: return 2.25
        }
    }

    static let baseCanvasSize = CGSize(width: 420, height: 360)

    var visualScale: CGFloat {
        switch self {
        case .praise: return 0.84
        case .whip: return 0.70
        }
    }

    var canvasSize: CGSize {
        CGSize(
            width: Self.baseCanvasSize.width * visualScale,
            height: Self.baseCanvasSize.height * visualScale
        )
    }

    var verticalCenterOffset: CGFloat {
        switch self {
        case .praise: return 90
        case .whip: return 10
        }
    }
}

@MainActor
final class ReactionCoordinator {
    private let settings = PetSettings()
    private let petReactionController = PetReactionController()
    private let soundPlayer = ReactionSoundPlayer()
    private let locatorPipeline: PetLocatorPipeline
    private var ratingPanel: OverlayPanel?
    private var animationPanel: OverlayPanel?
    private var welcomePanel: OverlayPanel?
    private var animationTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?

    init() {
        locatorPipeline = PetLocatorPipeline(locators: [
            AccessibilityPetLocator(),
            WindowPetLocator(),
            ElectronSavedBoundsPetLocator()
        ])
    }

    var isMouseHoverEnabled: Bool {
        get { settings.isMouseHoverEnabled }
        set { settings.isMouseHoverEnabled = newValue }
    }

    func showWelcome() {
        let view = WelcomeView(
            onDetect: { [weak self] in
                self?.welcomePanel?.orderOut(nil)
                self?.showRatingPrompt()
            },
            onClose: { [weak self] in
                self?.welcomePanel?.orderOut(nil)
            }
        )

        let panel = welcomePanel ?? OverlayPanel(interactive: true)
        let size = CGSize(width: 390, height: 224)
        panel.setContent(view: view, size: size)

        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        panel.setFrameOrigin(CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        ))
        panel.orderFrontRegardless()
        welcomePanel = panel
    }

    func showRatingPrompt() {
        welcomePanel?.orderOut(nil)
        animationTask?.cancel()
        animationPanel?.orderOut(nil)
        soundPlayer.stop()
        petReactionController.stop()
        locationTask?.cancel()

        let panel = ratingPanel ?? OverlayPanel(interactive: true)
        let locatingSize = CGSize(width: 250, height: 58)
        panel.setContent(view: LocatingPetView(), size: locatingSize)
        panel.setFrameOrigin(centeredOrigin(for: locatingSize))
        panel.orderFrontRegardless()
        ratingPanel = panel

        locationTask = Task { [weak self] in
            guard let self else { return }
            let location = await self.locatorPipeline.locatePet()
            guard !Task.isCancelled else { return }

            if let location {
                self.settings.saveAutomaticLocation(location)
                self.showRating(at: location)
            } else {
                self.showPetNotFound()
            }
        }
    }

    func play(_ kind: ReactionKind) {
        ratingPanel?.orderOut(nil)
        animationTask?.cancel()
        animationPanel?.orderOut(nil)
        soundPlayer.stop()
        petReactionController.stop()
        locationTask?.cancel()

        locationTask = Task { [weak self] in
            guard let self else { return }
            let location = await self.locatorPipeline.locatePet()
            guard !Task.isCancelled else { return }

            guard let location else {
                self.showPetNotFound()
                return
            }

            self.settings.saveAutomaticLocation(location)
            self.startAnimation(kind, at: location)
        }
    }

    private func startAnimation(_ kind: ReactionKind, at location: PetLocation) {
        let petPosition = location.interactionAnchor
        let canvasSize = kind.canvasSize
        let panel = OverlayPanel(interactive: false)
        panel.setContent(
            view: ReactionView(kind: kind, startedAt: Date()),
            size: canvasSize
        )
        panel.setFrameOrigin(
            CGPoint(
                x: petPosition.x - canvasSize.width / 2,
                y: petPosition.y + kind.verticalCenterOffset - canvasSize.height / 2
            )
        )
        panel.orderFrontRegardless()
        animationPanel = panel
        soundPlayer.play(kind)
        petReactionController.begin(
            kind,
            at: location,
            enablesHover: settings.isMouseHoverEnabled
        )

        animationTask = Task { [weak self] in
            let nanoseconds = UInt64(kind.duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.animationPanel?.orderOut(nil)
            self?.animationPanel = nil
        }
    }

    private func showRating(at location: PetLocation) {
        let ratingSize = CGSize(width: 72, height: 32)
        let view = RatingView(
            onPraise: { [weak self] in self?.play(.praise) },
            onWhip: { [weak self] in self?.play(.whip) }
        )
        let panel = ratingPanel ?? OverlayPanel(interactive: true)
        panel.setContent(view: view, size: ratingSize)
        panel.setFrameOrigin(ratingOrigin(near: location.frame, size: ratingSize))
        panel.orderFrontRegardless()
        ratingPanel = panel
    }

    private func showPetNotFound() {
        let view = PetNotFoundView(
            onRetry: { [weak self] in self?.showRatingPrompt() },
            onClose: { [weak self] in self?.ratingPanel?.orderOut(nil) }
        )
        let size = CGSize(width: 350, height: 164)
        let panel = ratingPanel ?? OverlayPanel(interactive: true)
        panel.setContent(view: view, size: size)
        panel.setFrameOrigin(centeredOrigin(for: size))
        panel.orderFrontRegardless()
        ratingPanel = panel
    }

    private func centeredOrigin(for size: CGSize) -> CGPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        return CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
    }

    private func ratingOrigin(near petFrame: CGRect, size: CGSize) -> CGPoint {
        // The Electron overlay is substantially wider than the visible pet.
        // Anchor from its center so transparent side padding cannot push the
        // rating controls far away from the pet.
        let visiblePetLeftOffset: CGFloat = 52
        let proposed = CGPoint(
            x: petFrame.midX - size.width - visiblePetLeftOffset,
            y: petFrame.minY + 70
        )
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(petFrame) }) ?? NSScreen.main else {
            return proposed
        }
        let visible = screen.visibleFrame
        return CGPoint(
            x: min(max(proposed.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(proposed.y, visible.minY + 8), visible.maxY - size.height - 8)
        )
    }
}
