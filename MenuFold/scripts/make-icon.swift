import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
let background = NSBezierPath(roundedRect: canvas.insetBy(dx: 36, dy: 36), xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.17, green: 0.38, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.45, green: 0.22, blue: 0.92, alpha: 1)
])!
gradient.draw(in: background, angle: -48)

NSColor.white.withAlphaComponent(0.18).setStroke()
background.lineWidth = 8
background.stroke()

let barRect = NSRect(x: 188, y: 604, width: 648, height: 92)
let bar = NSBezierPath(roundedRect: barRect, xRadius: 46, yRadius: 46)
NSColor.white.withAlphaComponent(0.95).setFill()
bar.fill()

for x in [244.0, 332.0, 420.0] {
    let dot = NSBezierPath(ovalIn: NSRect(x: x, y: 628, width: 44, height: 44))
    NSColor(calibratedRed: 0.24, green: 0.34, blue: 0.86, alpha: 1).setFill()
    dot.fill()
}

let folded = NSBezierPath(roundedRect: NSRect(x: 248, y: 332, width: 528, height: 206), xRadius: 62, yRadius: 62)
NSColor.white.withAlphaComponent(0.92).setFill()
folded.fill()

let chevron = NSBezierPath()
chevron.move(to: NSPoint(x: 430, y: 436))
chevron.line(to: NSPoint(x: 494, y: 386))
chevron.line(to: NSPoint(x: 558, y: 436))
chevron.lineWidth = 26
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
NSColor(calibratedRed: 0.31, green: 0.27, blue: 0.88, alpha: 1).setStroke()
chevron.stroke()

image.unlockFocus()

guard let output = CommandLine.arguments.dropFirst().first,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else { exit(1) }

try png.write(to: URL(fileURLWithPath: output))
