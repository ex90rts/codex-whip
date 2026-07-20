import AppKit
import CoreGraphics
import Foundation

enum PetWindowDiagnostics {
    private static let identityTokens = ["codex", "openai", "chatgpt", "electron"]

    static func run() async -> Bool {
        let applications = NSWorkspace.shared.runningApplications.compactMap { application -> String? in
            let name = application.localizedName ?? ""
            let bundleID = application.bundleIdentifier ?? ""
            let identity = "\(name) \(bundleID)".lowercased()
            guard identityTokens.contains(where: identity.contains) else { return nil }
            return "pid=\(application.processIdentifier) name=\(name) bundle=\(bundleID)"
        }

        print("[PET-DIAG] matching applications: \(applications.count)")
        applications.forEach { print("[PET-DIAG] app \($0)") }

        let windows = (CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []).compactMap(WindowDiagnostic.init)

        let relevantWindows = windows.filter { window in
            let identity = "\(window.ownerName) \(window.name)".lowercased()
            let ownerLooksRelevant = identityTokens.contains(where: identity.contains)
            let sizeLooksLikeOverlay = window.bounds.width >= 80
                && window.bounds.width <= 520
                && window.bounds.height >= 80
                && window.bounds.height <= 520
            return ownerLooksRelevant || sizeLooksLikeOverlay
        }

        print("[PET-DIAG] relevant windows: \(relevantWindows.count)")
        relevantWindows.forEach { print("[PET-DIAG] window \($0.description)") }

        if let location = await WindowPetLocator().locatePet() {
            print("[PET-DIAG] RESULT found source=\(location.source.rawValue) frame=\(location.frame) confidence=\(location.confidence) detail=\(location.detail)")
            return true
        }

        print("[PET-DIAG] RESULT not-found")
        return false
    }
}

private struct WindowDiagnostic {
    let id: UInt32
    let ownerPID: Int32
    let ownerName: String
    let name: String
    let bounds: CGRect
    let layer: Int
    let alpha: Double

    init?(_ dictionary: [String: Any]) {
        guard let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        id = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
        ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        ownerName = dictionary[kCGWindowOwnerName as String] as? String ?? ""
        name = dictionary[kCGWindowName as String] as? String ?? ""
        self.bounds = bounds
        layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    }

    var description: String {
        "id=\(id) pid=\(ownerPID) owner=\(ownerName.debugDescription) name=\(name.debugDescription) "
            + "bounds=(\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))) "
            + "layer=\(layer) alpha=\(String(format: "%.2f", alpha))"
    }
}
