// Draws the 1024-pixel app icon: a slip of paper shaped like a "p".
// Usage: swift make-icon.swift output.png
import AppKit

let side = 1024
guard CommandLine.arguments.count > 1,
      let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0
      ),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
else { fatalError("usage: make-icon output.png") }

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let peacock = color(0x0F5C63)
let paper = color(0xFFF6E6)
let marigold = color(0xF4A62A)

let context = graphics.cgContext

// A 100-unit tile with y pointing down, placed on Apple's 824-point icon grid.
context.translateBy(x: 100, y: 924)
context.scaleBy(x: 8.24, y: -8.24)

context.addPath(CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100),
    cornerWidth: 22, cornerHeight: 22, transform: nil
))
context.setFillColor(peacock)
context.fillPath()

context.translateBy(x: 9.2, y: 8.4)
context.scaleBy(x: 0.8, y: 0.8)

let slip = CGMutablePath()
slip.move(to: CGPoint(x: 34, y: 18))
slip.addLine(to: CGPoint(x: 68, y: 18))
slip.addQuadCurve(to: CGPoint(x: 76, y: 26), control: CGPoint(x: 76, y: 18))
slip.addLine(to: CGPoint(x: 76, y: 46))
slip.addLine(to: CGPoint(x: 60, y: 62))
slip.addLine(to: CGPoint(x: 40, y: 62))
slip.addLine(to: CGPoint(x: 40, y: 79))
slip.addArc(center: CGPoint(x: 33, y: 79), radius: 7, startAngle: 0, endAngle: .pi, clockwise: false)
slip.addLine(to: CGPoint(x: 26, y: 26))
slip.addQuadCurve(to: CGPoint(x: 34, y: 18), control: CGPoint(x: 26, y: 18))
slip.closeSubpath()
context.addPath(slip)
context.setFillColor(paper)
context.fillPath()

let fold = CGMutablePath()
fold.move(to: CGPoint(x: 76, y: 46))
fold.addLine(to: CGPoint(x: 60, y: 46))
fold.addLine(to: CGPoint(x: 60, y: 62))
fold.closeSubpath()
context.addPath(fold)
context.setFillColor(marigold)
context.fillPath()

context.addPath(CGPath(
    roundedRect: CGRect(x: 42, y: 31, width: 20, height: 6),
    cornerWidth: 3, cornerHeight: 3, transform: nil
))
context.setFillColor(peacock)
context.fillPath()

guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("could not encode") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
