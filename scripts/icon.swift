import AppKit

// «Dicho y escrito» (propuesta/logos.html, concepto 2): un globo con la voz que termina en el cursor de texto.
// Se dibuja en las coordenadas de propuesta/img/concepto-2-dicho-y-escrito.svg (512 × 512, y hacia abajo).

let out = CommandLine.arguments[1]
let size: CGFloat = 1024
let inset: CGFloat = 100
let tile = size - inset * 2
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: Int) -> NSColor {
	NSColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
	NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

// Del espacio del SVG al azulejo de 824 px centrado, con y hacia abajo como en el SVG.
ctx.translateBy(x: inset, y: size - inset)
ctx.scaleBy(x: tile / 512, y: -tile / 512)

let background = pill(0, 0, 512, 512, 112)
ctx.saveGState()
// La sombra va en coordenadas del dispositivo (y hacia arriba): no la voltea la transformación.
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
rgb(0x3b1fd1).setFill()
background.fill()
ctx.restoreGState()
ctx.saveGState()
background.addClip()
let gradient = CGGradient(colorsSpace: nil, colors: [rgb(0x7b5cff).cgColor, rgb(0x3b1fd1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 512, y: 512), options: [])
ctx.restoreGState()

let bubble = NSBezierPath()
bubble.move(to: NSPoint(x: 176, y: 136))
bubble.line(to: NSPoint(x: 336, y: 136))
bubble.appendArc(from: NSPoint(x: 408, y: 136), to: NSPoint(x: 408, y: 208), radius: 72)
bubble.line(to: NSPoint(x: 408, y: 272))
bubble.appendArc(from: NSPoint(x: 408, y: 344), to: NSPoint(x: 336, y: 344), radius: 72)
bubble.line(to: NSPoint(x: 236, y: 344))
bubble.line(to: NSPoint(x: 148, y: 404))
bubble.line(to: NSPoint(x: 176, y: 344))
bubble.appendArc(from: NSPoint(x: 104, y: 344), to: NSPoint(x: 104, y: 272), radius: 72)
bubble.line(to: NSPoint(x: 104, y: 208))
bubble.appendArc(from: NSPoint(x: 104, y: 136), to: NSPoint(x: 176, y: 136), radius: 72)
bubble.close()
rgb(0xd4ff3a).setFill()
bubble.fill()

rgb(0x24106b).setFill()
for path in [
	pill(163, 218, 18, 44, 9), pill(195, 192, 18, 96, 9), pill(227, 208, 18, 64, 9), // la voz
	pill(308, 178, 16, 124, 4), pill(284, 172, 64, 16, 8), pill(284, 292, 64, 16, 8), // el cursor
] {
	path.fill()
}

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
