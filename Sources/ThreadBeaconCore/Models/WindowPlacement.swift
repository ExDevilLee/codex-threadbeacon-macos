public struct WindowGeometry: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct DisplayGeometry: Equatable, Sendable {
    public let identifier: String
    public let visibleFrame: WindowGeometry

    public init(identifier: String, visibleFrame: WindowGeometry) {
        self.identifier = identifier
        self.visibleFrame = visibleFrame
    }
}

public struct WindowPlacement: Codable, Equatable, Sendable {
    public let displayIdentifier: String
    public let frame: WindowGeometry

    public init(displayIdentifier: String, frame: WindowGeometry) {
        self.displayIdentifier = displayIdentifier
        self.frame = frame
    }
}

public enum WindowPlacementResolver {
    public static func resolve(
        _ placement: WindowPlacement,
        displays: [DisplayGeometry],
        fallbackDisplayIdentifier: String?
    ) -> WindowPlacement? {
        guard !displays.isEmpty else { return nil }
        let display = displays.first { $0.identifier == placement.displayIdentifier }
            ?? fallbackDisplayIdentifier.flatMap { fallback in
                displays.first { $0.identifier == fallback }
            }
            ?? displays[0]
        let visible = display.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return nil }

        let width = min(max(1, placement.frame.width), visible.width)
        let height = min(max(1, placement.frame.height), visible.height)
        let maximumX = visible.x + visible.width - width
        let maximumY = visible.y + visible.height - height
        let x = min(max(placement.frame.x, visible.x), maximumX)
        let y = min(max(placement.frame.y, visible.y), maximumY)

        return WindowPlacement(
            displayIdentifier: display.identifier,
            frame: WindowGeometry(x: x, y: y, width: width, height: height)
        )
    }
}
