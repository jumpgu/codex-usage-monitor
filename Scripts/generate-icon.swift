import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Packaging/AppIcon.iconset", isDirectory: true)
let output = root.appendingPathComponent("Packaging/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.current?.imageInterpolation = .high

    let corner = CGFloat(size) * 0.22
    let background = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.045, dy: CGFloat(size) * 0.045), xRadius: corner, yRadius: corner)
    NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 1).setFill()
    background.fill()

    let inset = CGFloat(size) * 0.13
    let panel = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: CGFloat(size) * 0.16, yRadius: CGFloat(size) * 0.16)
    NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1).setFill()
    panel.fill()

    let center = NSPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.42)
    let radius = CGFloat(size) * 0.28
    let lineWidth = max(2, CGFloat(size) * 0.055)

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 200, endAngle: -20, clockwise: true)
    track.lineWidth = lineWidth
    track.lineCapStyle = .round
    NSColor(calibratedRed: 0.28, green: 0.34, blue: 0.42, alpha: 1).setStroke()
    track.stroke()

    let gauge = NSBezierPath()
    gauge.appendArc(withCenter: center, radius: radius, startAngle: 200, endAngle: 34, clockwise: true)
    gauge.lineWidth = lineWidth
    gauge.lineCapStyle = .round
    NSColor(calibratedRed: 0.20, green: 0.86, blue: 0.52, alpha: 1).setStroke()
    gauge.stroke()

    let needle = NSBezierPath()
    needle.move(to: center)
    let angle = CGFloat(38) * .pi / 180
    needle.line(to: NSPoint(x: center.x + cos(angle) * radius * 0.78, y: center.y + sin(angle) * radius * 0.78))
    needle.lineWidth = max(2, CGFloat(size) * 0.025)
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()

    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - CGFloat(size) * 0.035, y: center.y - CGFloat(size) * 0.035, width: CGFloat(size) * 0.07, height: CGFloat(size) * 0.07)).fill()

    let text = "C" as NSString
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let fontSize = CGFloat(size) * 0.28
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .black),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    text.draw(in: NSRect(x: 0, y: CGFloat(size) * 0.56, width: CGFloat(size), height: CGFloat(size) * 0.34), withAttributes: attrs)

    return image
}

for (name, size) in sizes {
    let image = drawIcon(size: size)
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "CodexUsageIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render \(name)"])
    }
    try png.write(to: iconset.appendingPathComponent(name))
}
