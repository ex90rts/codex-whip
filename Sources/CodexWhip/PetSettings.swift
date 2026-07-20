import AppKit

final class PetSettings {
    private enum Key {
        static let automaticX = "automaticLocation.x"
        static let automaticY = "automaticLocation.y"
        static let hoverEnabled = "mouseHoverEnabled"
        static let automaticSource = "automaticLocation.source"
        static let automaticConfidence = "automaticLocation.confidence"
    }

    func saveAutomaticLocation(_ location: PetLocation) {
        defaults.set(location.center.x, forKey: Key.automaticX)
        defaults.set(location.center.y, forKey: Key.automaticY)
        defaults.set(location.source.rawValue, forKey: Key.automaticSource)
        defaults.set(location.confidence, forKey: Key.automaticConfidence)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isMouseHoverEnabled: Bool {
        get {
            defaults.object(forKey: Key.hoverEnabled) == nil
                ? true
                : defaults.bool(forKey: Key.hoverEnabled)
        }
        set { defaults.set(newValue, forKey: Key.hoverEnabled) }
    }

}
