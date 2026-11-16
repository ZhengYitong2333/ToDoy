import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 58,y: 58,width: 908,height: 908)
let tile = NSBezierPath(roundedRect: rect,xRadius: 210,yRadius: 210)
NSGradient(starting: NSColor(white: 0.96, alpha: 1), ending: .white)!.draw(in: tile, angle: 82)
NSColor(white: 0.84, alpha: 0.65).setStroke()
tile.lineWidth = 3
tile.stroke()

// Draw the two bands inside one check silhouette to keep the outer corners continuous.
let check = NSBezierPath()
check.move(to: NSPoint(x: 205, y: 505))
for point in [NSPoint(x: 310, y: 610), NSPoint(x: 435, y: 485),
              NSPoint(x: 712, y: 762), NSPoint(x: 820, y: 654), NSPoint(x: 435, y: 269)] {
    check.line(to: point)
}
check.close()
check.lineJoinStyle = .round
check.lineWidth = 12
let forest = NSColor(srgbRed: 0.015, green: 0.47, blue: 0.24, alpha: 1)
forest.setFill()
forest.setStroke()
check.fill()
check.stroke()
let risingBand = NSBezierPath()
risingBand.move(to: NSPoint(x: 330, y: 374))
risingBand.line(to: NSPoint(x: 712, y: 756))
risingBand.line(to: NSPoint(x: 815, y: 654))
risingBand.line(to: NSPoint(x: 435, y: 274))
risingBand.close()
risingBand.lineWidth = 12
risingBand.lineJoinStyle = .round
let leaf = NSColor(srgbRed: 0.09, green: 0.68, blue: 0.34, alpha: 1)
leaf.setFill()
leaf.setStroke()
risingBand.fill()
risingBand.stroke()
image.unlockFocus()
try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
