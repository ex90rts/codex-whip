import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    init(interactive: Bool) {
        let style: NSWindow.StyleMask = interactive
            ? [.borderless, .nonactivatingPanel]
            : [.borderless]

        super.init(
            contentRect: .zero,
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        ignoresMouseEvents = !interactive
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    func setContent<V: View>(view: V, size: CGSize) {
        let hostingView = TransparentHostingView(rootView: view.background(Color.clear))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        contentView = hostingView
        setContentSize(size)
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}
