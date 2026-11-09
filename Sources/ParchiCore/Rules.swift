import CoreGraphics
import Foundation

public enum Retention {
    public static let trashDays = 7

    /// Trashed items whose time in the Trash has run out.
    public static func expired(_ items: [Item], now: Date = Date()) -> [Item] {
        let limit = TimeInterval(trashDays) * 24 * 60 * 60
        return items.filter { item in
            guard item.state == .trashed, let trashedAt = item.trashedAt else { return false }
            return now.timeIntervalSince(trashedAt) >= limit
        }
    }
}

public enum TodoOrdering {
    /// The order tasks appear in. Completed tasks keep their relative order at the bottom.
    public static func display(_ tasks: [TodoTask], completedLast: Bool) -> [TodoTask] {
        guard completedLast else { return tasks }
        return tasks.filter { !$0.done } + tasks.filter(\.done)
    }
}

public enum WindowPlacement {
    private static let handleHeight: CGFloat = 24
    private static let minimumHandleWidth: CGFloat = 48

    /// Returns `frame` unchanged if its drag handle can be reached on one of `screens`,
    /// otherwise moves it (and shrinks it if needed) onto the nearest screen.
    public static func onScreen(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard !screens.isEmpty else { return frame }

        let handle = CGRect(
            x: frame.minX,
            y: frame.maxY - handleHeight,
            width: frame.width,
            height: handleHeight
        )
        let reachable = screens.contains { screen in
            let overlap = screen.intersection(handle)
            return !overlap.isNull
                && overlap.width >= min(minimumHandleWidth, frame.width)
                && overlap.height >= handleHeight
        }
        if reachable { return frame }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        let nearest = screens.min { a, b in
            distanceSquared(center, CGPoint(x: a.midX, y: a.midY))
                < distanceSquared(center, CGPoint(x: b.midX, y: b.midY))
        }!

        var result = frame
        result.size.width = min(frame.width, nearest.width)
        result.size.height = min(frame.height, nearest.height)
        result.origin.x = min(max(frame.minX, nearest.minX), nearest.maxX - result.width)
        result.origin.y = min(max(frame.minY, nearest.minY), nearest.maxY - result.height)
        return result
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    /// Where the `index`-th new window goes: stepping down and left from the top right.
    public static func cascade(index: Int, size: CGSize, in visible: CGRect) -> CGRect {
        let step: CGFloat = 28
        let perColumn = 10
        let row = CGFloat(index % perColumn)
        let column = CGFloat((index / perColumn) % 6)
        let margin: CGFloat = 40

        var x = visible.maxX - margin - size.width - row * step - column * (size.width + step)
        var y = visible.maxY - margin - size.height - row * step
        x = max(visible.minX, x)
        y = max(visible.minY, y)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Where a popup of `size` goes for a card at `anchor`: to its right, else to its left,
    /// else over it, and always fully on the card's screen.
    public static func popupFrame(anchor: CGRect, size: CGSize, screens: [CGRect]) -> CGRect {
        let gap: CGFloat = 12
        let center = CGPoint(x: anchor.midX, y: anchor.midY)
        let screen = screens.first { $0.contains(center) }
            ?? screens.min { a, b in
                distanceSquared(center, CGPoint(x: a.midX, y: a.midY))
                    < distanceSquared(center, CGPoint(x: b.midX, y: b.midY))
            }
            ?? anchor

        var x: CGFloat
        if anchor.maxX + gap + size.width <= screen.maxX {
            x = anchor.maxX + gap
        } else if anchor.minX - gap - size.width >= screen.minX {
            x = anchor.minX - gap - size.width
        } else {
            x = anchor.midX - size.width / 2
        }
        var y = anchor.maxY - size.height

        x = min(max(x, screen.minX), screen.maxX - size.width)
        y = min(max(y, screen.minY), screen.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    public static let captionHeight: CGFloat = 30
    public static let tapeBorderRatio: CGFloat = 0.03
    /// Width over height of the arched look, which crops every photo to the same shape.
    private static let jharokhaAspect: CGFloat = 224.0 / 310.0

    /// Space around the picture for each look, as fractions of the window's width.
    public static func photoInsets(_ look: PhotoLook) -> (side: CGFloat, top: CGFloat, bottom: CGFloat) {
        switch look {
        case .stamp: return (1.0 / 15.0, 1.0 / 15.0, 1.0 / 15.0)
        case .tape: return (0.09, 0.14, 0.09)
        case .album: return (0.075, 0.075, 0.075)
        case .jharokha: return (0.0357, 0.0357, 0.0357)
        case .bare: return (0, 0, 0)
        }
    }

    /// Window height for a photo of the given aspect ratio at `width`.
    public static func photoHeight(width: CGFloat, aspect: CGFloat, look: PhotoLook, hasCaption: Bool = false) -> CGFloat {
        if look == .jharokha { return (width / jharokhaAspect).rounded() }
        let safeAspect = aspect > 0 ? aspect : 1
        let insets = photoInsets(look)
        let picture = width * (1 - 2 * insets.side) / safeAspect
        let caption = look.showsCaption && hasCaption ? captionHeight : 0
        return (picture + width * (insets.top + insets.bottom) + caption).rounded()
    }

    /// The inverse of `photoHeight`, for resizing a photo from its top or bottom edge.
    public static func photoWidth(height: CGFloat, aspect: CGFloat, look: PhotoLook, hasCaption: Bool = false) -> CGFloat {
        if look == .jharokha { return (height * jharokhaAspect).rounded() }
        let safeAspect = aspect > 0 ? aspect : 1
        let insets = photoInsets(look)
        let caption = look.showsCaption && hasCaption ? captionHeight : 0
        let perWidth = (1 - 2 * insets.side) / safeAspect + insets.top + insets.bottom
        return ((height - caption) / perWidth).rounded()
    }
}

/// A command received through the `parchi://` URL scheme.
public enum URLCommand: Equatable, Sendable {
    case newNote(title: String, text: String)
    case newTodo(title: String, items: [String])
    case openMain

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "parchi" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }
        switch url.host?.lowercased() {
        case "new":
            self = .newNote(title: query["title"] ?? "", text: query["text"] ?? "")
        case "todo":
            let items = (query["items"] ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            self = .newTodo(title: query["title"] ?? "", items: items)
        case "open":
            self = .openMain
        default:
            return nil
        }
    }
}
