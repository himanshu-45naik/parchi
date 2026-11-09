import AppKit
import ParchiCore
import SwiftUI

/// A photo drawn in one of its looks. Its size comes from `WindowPlacement.photoHeight`,
/// which uses the same insets, so the picture keeps its proportions.
struct PhotoContent: View {
    let image: NSImage?
    let item: Item

    var body: some View {
        GeometryReader { proxy in
            look(in: proxy.size)
        }
    }

    private var showsCaption: Bool { item.photoLook.showsCaption && item.hasCaption }

    @ViewBuilder
    private func look(in size: CGSize) -> some View {
        let insets = WindowPlacement.photoInsets(item.photoLook)
        let side = size.width * insets.side
        let top = size.width * insets.top
        let bottom = size.width * insets.bottom
        let caption = showsCaption ? WindowPlacement.captionHeight : 0
        let pictureSize = CGSize(
            width: max(size.width - 2 * side, 1),
            height: max(size.height - top - bottom - caption, 1)
        )

        switch item.photoLook {
        case .stamp:
            pictureWithCaption(pictureSize)
                .padding(.top, top)
                .padding(.bottom, bottom)
                .padding(.horizontal, side)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: NSColor(hex: 0xFFFDF7)))
                .clipShape(StampShape(), style: FillStyle(eoFill: true))

        case .tape:
            let border = size.width * WindowPlacement.tapeBorderRatio
            pictureWithCaption(pictureSize)
                .padding(border)
                .background(Color.white)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Brand.marigold.opacity(0.78))
                        .frame(width: size.width * 0.35, height: size.width * 0.1)
                        .rotationEffect(.degrees(3))
                        .offset(y: -size.width * 0.05)
                }
                .rotationEffect(.degrees(-2.5))
                .padding(.top, top - border)
                .padding(.bottom, bottom - border)
                .padding(.horizontal, side - border)
                .frame(width: size.width, height: size.height)

        case .album:
            let reach = size.width * 0.025
            VStack(spacing: 0) {
                picture(pictureSize)
                    .overlay(
                        AlbumCorners(length: size.width * 0.108)
                            .fill(Color(nsColor: NSColor(hex: 0x2B2A26)))
                            .padding(-reach)
                    )
                captionLabel
            }
            .padding(.top, top)
            .padding(.bottom, bottom)
            .padding(.horizontal, side)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: NSColor(hex: 0xEFE6D2)))

        case .jharokha:
            ZStack {
                ArchShape(bottomRadius: 6).fill(Color(nsColor: Brand.paper))
                picture(pictureSize).clipShape(ArchShape(bottomRadius: 2))
            }
            .frame(width: size.width, height: size.height)

        case .bare:
            picture(size)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2))
                )
        }
    }

    private func pictureWithCaption(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            picture(size)
            captionLabel
        }
    }

    @ViewBuilder
    private var captionLabel: some View {
        if showsCaption {
            Text(item.title)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(nsColor: Highlight.inkOnHighlight))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: WindowPlacement.captionHeight)
        }
    }

    @ViewBuilder
    private func picture(_ size: CGSize) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// A rectangle with postage-stamp bites along every edge. Fill it even-odd.
struct StampShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)

        func bite(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }

        let across = max(Int((rect.width / 16).rounded()), 1)
        let pitch = rect.width / CGFloat(across)
        let radius = pitch * 0.31
        for index in 0..<across {
            let x = rect.minX + (CGFloat(index) + 0.5) * pitch
            bite(x, rect.minY, radius)
            bite(x, rect.maxY, radius)
        }

        let down = max(Int((rect.height / pitch).rounded()), 1)
        let downPitch = rect.height / CGFloat(down)
        for index in 0..<down {
            let y = rect.minY + (CGFloat(index) + 0.5) * downPitch
            bite(rect.minX, y, radius)
            bite(rect.maxX, y, radius)
        }
        return path
    }
}

/// A window with a rounded arch for its top.
struct ArchShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let arch = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arch))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + arch),
            radius: arch,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            radius: bottomRadius
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            radius: bottomRadius
        )
        path.closeSubpath()
        return path
    }
}

/// The four triangles that hold a photo to an album page.
struct AlbumCorners: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) {
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.closeSubpath()
        }
        triangle(
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX + length, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.minY + length)
        )
        triangle(
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX - length, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + length)
        )
        triangle(
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX + length, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - length)
        )
        triangle(
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.maxX - length, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY - length)
        )
        return path
    }
}
