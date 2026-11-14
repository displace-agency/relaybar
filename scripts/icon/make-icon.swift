// Quota app icon generator: "flat slash and meter ring". Run: swift scripts/icon/make-icon.swift
import AppKit
import CoreGraphics

let cs = CGColorSpaceCreateDeviceRGB()
func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
}
func grad(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

// Continuous-corner squircle (superellipse blend), in a 1024 design space.
func squircle(_ r: CGRect, n: CGFloat = 4.3) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func render(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    let k = CGFloat(px) / 1024
    ctx.scaleBy(x: k, y: k)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = squircle(body)
    let ink = col(0x0F0F10)

    // Standard soft drop shadow under the body
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 28 * k, color: col(0x000000, 0.45))
    ctx.setFillColor(ink)
    ctx.addPath(path); ctx.fillPath()
    ctx.restoreGState()

    // Flat body, then the glyph (see quota-icon.svg, 512 viewBox, y-down) mapped onto it
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.setFillColor(ink)
    ctx.fill(body)
    let s = 824.0 / 512.0
    ctx.translateBy(x: 100, y: 924)
    ctx.scaleBy(x: s, y: -s)          // SVG space, y-down
    ctx.translateBy(x: 14, y: 0)

    // Slash
    ctx.setFillColor(col(0xFFFFFF))
    ctx.move(to: CGPoint(x: 137, y: 183)); ctx.addLine(to: CGPoint(x: 166, y: 183))
    ctx.addLine(to: CGPoint(x: 138, y: 330)); ctx.addLine(to: CGPoint(x: 108, y: 330))
    ctx.closePath(); ctx.fillPath()

    // Ring track (26% white) and 270 degree arc, 3 o'clock clockwise to 12 o'clock
    let c = CGPoint(x: 276, y: 256.5)
    ctx.setLineWidth(40)
    ctx.setStrokeColor(col(0xFFFFFF, 0.26))
    ctx.addArc(center: c, radius: 54, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(col(0xFFFFFF))
    ctx.setLineCap(.round)
    ctx.addArc(center: c, radius: 54, startAngle: 0, endAngle: 1.5 * .pi, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let dir = FileManager.default.currentDirectoryPath + "/scripts/icon"
let out = dir + "/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: out)
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
_ = here

for base in [16, 32, 128, 256, 512] {
    write(render(px: base), "\(out)/icon_\(base)x\(base).png")
    write(render(px: base * 2), "\(out)/icon_\(base)x\(base)@2x.png")
}
let big = render(px: 1024)
write(big, dir + "/preview-1024.png")

// Contact sheet
let sizes = [16, 32, 64, 128, 256]
let pad = 30
let rowH = 256 + pad * 2
let totalW = sizes.reduce(0, +) + pad * (sizes.count + 1)
let sheet = CGContext(data: nil, width: totalW, height: rowH * 2, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for (row, bg) in [(1, 0xF5F5F7), (0, 0x1E1E1E)] {
    sheet.setFillColor(col(UInt32(bg)))
    sheet.fill(CGRect(x: 0, y: row * rowH, width: totalW, height: rowH))
    var x = pad
    for s in sizes {
        let y = row * rowH + (rowH - s) / 2
        sheet.draw(render(px: s), in: CGRect(x: x, y: y, width: s, height: s))
        x += s + pad
    }
}
write(sheet.makeImage()!, dir + "/preview-sizes.png")
print("done")
