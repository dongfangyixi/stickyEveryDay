import AppKit

enum WindowFrameStore {
    static func storedFrame(from frame: NSRect) -> StoredWindowFrame {
        StoredWindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
    }

    static func frame(from storedFrame: StoredWindowFrame) -> NSRect {
        NSRect(
            x: storedFrame.x,
            y: storedFrame.y,
            width: storedFrame.width,
            height: storedFrame.height
        )
    }

    static func defaultFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1200, height: 800)
        let size = NSSize(width: 380, height: 560)

        return NSRect(
            x: visibleFrame.maxX - size.width - 32,
            y: visibleFrame.maxY - size.height - 48,
            width: size.width,
            height: size.height
        )
    }

    static func usableFrame(from storedFrame: StoredWindowFrame?) -> NSRect {
        let candidate = storedFrame.map(frame(from:)) ?? defaultFrame()
        let minimumSize = NSSize(width: 320, height: 420)

        var frame = candidate
        frame.size.width = max(frame.size.width, minimumSize.width)
        frame.size.height = max(frame.size.height, minimumSize.height)

        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main else {
            return frame
        }

        let visibleFrame = screen.visibleFrame
        guard visibleFrame.intersects(frame) else {
            return defaultFrame()
        }

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }

        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }

        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }

        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        return frame
    }
}

