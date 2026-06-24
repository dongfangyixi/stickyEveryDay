import AppKit

enum PinWindowService {
    static func apply(isPinned: Bool, to window: NSWindow) {
        window.level = isPinned ? .floating : .normal

        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        if isPinned {
            behavior.insert(.canJoinAllSpaces)
            behavior.insert(.stationary)
        }

        window.collectionBehavior = behavior
    }
}

