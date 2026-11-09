import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    func swatch(size: CGFloat = 12) -> NSImage {
        let fill = self
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }
}

enum Brand {
    static let marigold = Color(nsColor: NSColor(hex: 0xF4A62A))
    static let paper = NSColor(hex: 0xFFF6E6)
    static let ink = NSColor(hex: 0x1B1A17)
}

/// The kinds of type a theme can use. All are built into macOS.
enum CardFace {
    case rounded, system, serif, mono, hand

    var design: NSFontDescriptor.SystemDesign? {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        case .system, .hand: return nil
        }
    }
}

struct CardTheme: Identifiable {
    enum Edge { case slip, torn }
    enum Decoration { case none, notebook, stamp }

    let id: String
    let name: String
    let surface: NSColor
    let ink: NSColor
    let fold: NSColor
    var titleColor: NSColor?
    var titleFace: CardFace = .rounded
    var bodyFace: CardFace = .system
    var edge: Edge = .slip
    var decoration: Decoration = .none
    var insets = EdgeInsets(top: 22, leading: 24, bottom: 22, trailing: 24)
    /// A fixed line height, for text that has to sit on printed lines.
    var lineHeight: CGFloat?
    var isDark = false
    var squareChecks = false

    var color: Color { Color(nsColor: surface) }
    var inkColor: Color { Color(nsColor: ink) }

    static let all: [CardTheme] = [
        CardTheme(id: "kagaz", name: "Kagaz", surface: NSColor(hex: 0xFBF6EA), ink: NSColor(hex: 0x23201A), fold: NSColor(hex: 0xE4D9C2)),
        CardTheme(id: "haldi", name: "Haldi", surface: NSColor(hex: 0xF6C445), ink: NSColor(hex: 0x2A1F05), fold: NSColor(hex: 0xD9A52B)),
        CardTheme(id: "gulabi", name: "Gulabi", surface: NSColor(hex: 0xF5C6CF), ink: NSColor(hex: 0x3A1720), fold: NSColor(hex: 0xDFA2AF)),
        CardTheme(id: "neem", name: "Neem", surface: NSColor(hex: 0xC9DDB4), ink: NSColor(hex: 0x1E2C14), fold: NSColor(hex: 0xAAC392)),
        CardTheme(
            id: "raat", name: "Raat", surface: NSColor(hex: 0x16324A), ink: NSColor(hex: 0xF5EFE2), fold: NSColor(hex: 0x2A4E6C),
            titleColor: NSColor(hex: 0xF4B942), isDark: true
        ),
        CardTheme(
            id: "rasid", name: "Rasid", surface: NSColor(hex: 0xF7F5EF), ink: NSColor(hex: 0x26241F), fold: NSColor(hex: 0xF7F5EF),
            titleFace: .mono, bodyFace: .mono, edge: .torn,
            insets: EdgeInsets(top: 20, leading: 24, bottom: 22, trailing: 24), squareChecks: true
        ),
        CardTheme(
            id: "copy", name: "Copy", surface: NSColor(hex: 0xFDFDF8), ink: NSColor(hex: 0x1E2A3A), fold: NSColor(hex: 0xE2E2D8),
            titleFace: .hand, bodyFace: .hand, decoration: .notebook,
            insets: EdgeInsets(top: 26, leading: 50, bottom: 20, trailing: 22), lineHeight: 27
        ),
        CardTheme(
            id: "inland", name: "Inland", surface: NSColor(hex: 0xC7DCF1), ink: NSColor(hex: 0x12304E), fold: NSColor(hex: 0xA5C2DF),
            titleFace: .serif, bodyFace: .serif, decoration: .stamp,
            insets: EdgeInsets(top: 22, leading: 24, bottom: 22, trailing: 72)
        ),
    ]

    static func find(_ id: String) -> CardTheme {
        all.first { $0.id == id } ?? all[0]
    }
}

struct Highlight: Identifiable {
    let id: String
    let name: String
    let color: NSColor

    static let inkOnHighlight = NSColor(hex: 0x24211C)

    static let all: [Highlight] = [
        Highlight(id: "yellow", name: "Yellow", color: NSColor(hex: 0xF9E04B)),
        Highlight(id: "green", name: "Green", color: NSColor(hex: 0xA8E67A)),
        Highlight(id: "blue", name: "Blue", color: NSColor(hex: 0x9CCBFF)),
        Highlight(id: "pink", name: "Pink", color: NSColor(hex: 0xFFA9CF)),
        Highlight(id: "purple", name: "Purple", color: NSColor(hex: 0xCDB4F7)),
        Highlight(id: "orange", name: "Orange", color: NSColor(hex: 0xFFBE73)),
        Highlight(id: "red", name: "Red", color: NSColor(hex: 0xFF9C8F)),
        Highlight(id: "gray", name: "Gray", color: NSColor(hex: 0xC9CCD1)),
    ]
}

enum FontChoices {
    static let suggested = ["Noteworthy", "Marker Felt", "Bradley Hand", "Chalkboard", "Georgia", "Avenir Next", "Menlo"]

    static let all: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted()
}

/// The slip of paper shaped like a "p" that is Parchi's logo.
/// Drawn in the coordinates it was designed in: x 26 to 76, y 18 to 86, y pointing down.
enum ParchiMark {
    static let bounds = CGRect(x: 26, y: 18, width: 50, height: 68)

    static func slip() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 34, y: 18))
        path.addLine(to: CGPoint(x: 68, y: 18))
        path.addQuadCurve(to: CGPoint(x: 76, y: 26), control: CGPoint(x: 76, y: 18))
        path.addLine(to: CGPoint(x: 76, y: 46))
        path.addLine(to: CGPoint(x: 60, y: 62))
        path.addLine(to: CGPoint(x: 40, y: 62))
        path.addLine(to: CGPoint(x: 40, y: 79))
        path.addArc(center: CGPoint(x: 33, y: 79), radius: 7, startAngle: 0, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: 26, y: 26))
        path.addQuadCurve(to: CGPoint(x: 34, y: 18), control: CGPoint(x: 26, y: 18))
        path.closeSubpath()
        return path
    }

    static func menuBarImage() -> NSImage {
        let height: CGFloat = 18
        let scale = height / bounds.height
        let size = NSSize(width: (bounds.width * scale).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.addPath(slip())
            context.addPath(CGPath(
                roundedRect: CGRect(x: 42, y: 31, width: 20, height: 6),
                cornerWidth: 3, cornerHeight: 3, transform: nil
            ))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Parchi"
        return image
    }
}

/// Small rounded corners, and the bottom right corner folded away.
struct SlipShape: Shape {
    var radius: CGFloat = 9
    var fold: CGFloat = FoldCorner.size

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}

/// A receipt: nearly square at the top, torn teeth along the bottom.
struct TornShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = 3
        let depth: CGFloat = 8
        let teeth = max(Int((rect.width / 10).rounded(.up)), 1)
        let step = rect.width / CGFloat(teeth)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + corner),
            radius: corner
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        for index in 0..<teeth {
            let right = rect.maxX - CGFloat(index) * step
            path.addLine(to: CGPoint(x: right - step / 2, y: rect.maxY - depth))
            path.addLine(to: CGPoint(x: right - step, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + corner, y: rect.minY),
            radius: corner
        )
        path.closeSubpath()
        return path
    }
}

/// The turned-over tip of paper in the corner that `SlipShape` cuts away.
struct FoldCorner: View {
    static let size: CGFloat = 20
    let color: NSColor

    var body: some View {
        Canvas { context, canvas in
            var path = Path()
            path.move(to: CGPoint(x: canvas.width, y: canvas.height - Self.size))
            path.addLine(to: CGPoint(x: canvas.width - Self.size, y: canvas.height - Self.size))
            path.addLine(to: CGPoint(x: canvas.width - Self.size, y: canvas.height))
            path.closeSubpath()
            context.fill(path, with: .color(Color(nsColor: color)))
        }
        .allowsHitTesting(false)
    }
}

/// A theme's paper. Editors turn the decoration off, since their controls sit near the edges.
struct ThemeBackground: View {
    let theme: CardTheme
    var decorated = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.color
            if decorated, theme.decoration == .notebook {
                NotebookLines()
            }
            if decorated, theme.decoration == .stamp {
                StampMark(ink: theme.ink)
                    .frame(width: 42, height: 50)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct NotebookLines: View {
    var body: some View {
        Canvas { context, size in
            let rule = Color(nsColor: NSColor(hex: 0xBFD4EA))
            for y in stride(from: 26.0, to: size.height, by: 27) {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(rule))
            }
            context.fill(
                Path(CGRect(x: 36, y: 0, width: 1, height: size.height)),
                with: .color(Color(nsColor: NSColor(hex: 0xE58A8A)))
            )
        }
    }
}

/// A postage stamp carrying the Parchi mark.
private struct StampMark: View {
    let ink: NSColor

    var body: some View {
        Canvas { context, size in
            let frame = Path(CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            context.fill(frame, with: .color(Color(nsColor: NSColor(hex: 0xF3F8FD))))
            context.stroke(
                frame,
                with: .color(Color(nsColor: ink)),
                style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
            )

            let scale: CGFloat = 0.5
            let bounds = ParchiMark.bounds
            let offset = CGAffineTransform(
                translationX: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            )
            let mark = Path(ParchiMark.slip())
                .applying(CGAffineTransform(scaleX: scale, y: scale))
                .applying(offset)
            context.fill(mark, with: .color(Color(nsColor: ink)))
        }
    }
}
