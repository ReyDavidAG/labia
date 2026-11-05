import AppKit

let out = CommandLine.arguments[1]
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let inset: CGFloat = 100
let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.13, green: 0.15, blue: 0.2, alpha: 1), NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)])!.draw(in: path, angle: -90)
NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
let heights: [CGFloat] = [0.3, 0.54, 0.74, 0.46, 0.24]
let barWidth: CGFloat = 64, gap: CGFloat = 40
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
for (i, h) in heights.enumerated() {
	let height = tile.height * h
	let rect = NSRect(x: tile.midX - total / 2 + CGFloat(i) * (barWidth + gap), y: tile.midY - height / 2, width: barWidth, height: height)
	(i == 2 ? NSColor(red: 0.5, green: 0.59, blue: 1, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
	NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
