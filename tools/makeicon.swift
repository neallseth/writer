// Renders the Writer app icon: a paper squircle with lines of ink,
// one scratched out. Run via tools/makeicon.sh, which wraps this in
// an .icns file.
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// macOS-style squircle, 824pt centered on a transparent canvas
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

// warm paper background with a faint vertical gradient
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.93, alpha: 1),
    ending: NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.85, alpha: 1)
)
gradient?.draw(in: squircle, angle: -90)

let ink = NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1)
let scratch = NSColor(calibratedRed: 0.72, green: 0.18, blue: 0.14, alpha: 1)
let accent = NSColor(calibratedRed: 0.90, green: 0.55, blue: 0.15, alpha: 1)

func line(from: NSPoint, to: NSPoint, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

// four lines of "text"
line(from: NSPoint(x: 240, y: 700), to: NSPoint(x: 784, y: 700), width: 56, color: ink)
line(from: NSPoint(x: 240, y: 560), to: NSPoint(x: 690, y: 560), width: 56, color: ink)
line(from: NSPoint(x: 240, y: 420), to: NSPoint(x: 760, y: 420), width: 56, color: ink)
line(from: NSPoint(x: 240, y: 280), to: NSPoint(x: 520, y: 280), width: 56, color: ink)

// the scratch-out through line two, slightly tilted like a pen stroke
line(from: NSPoint(x: 205, y: 542), to: NSPoint(x: 726, y: 582), width: 30, color: scratch)

// the cursor, mid-thought on the last line
let cursor = NSBezierPath(
    roundedRect: NSRect(x: 570, y: 234, width: 44, height: 92),
    xRadius: 12, yRadius: 12
)
accent.setFill()
cursor.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
