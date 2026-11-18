import XCTest
import SwiftUI
import AppKit

/// Offscreen rendering that sizes the bitmap to the popover's fitted height, like the real popover.
enum RenderSupport {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 520

    @MainActor
    static func spin(_ hosting: NSView) {
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        hosting.layoutSubtreeIfNeeded()
    }

    /// Height the popover would take for this view (content plus chrome, capped at the maximum).
    @MainActor
    static func fittedHeight<V: View>(_ view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: maxHeight)
        spin(hosting)
        return ceil(hosting.fittingSize.height)
    }

    /// Renders at `scale`x with the bitmap exactly as tall as the fitted popover. `appearance` is the host's
    /// macOS appearance, to prove the view forces its own light look.
    @MainActor
    static func render<V: View>(_ view: V, scale: CGFloat, appearance: NSAppearance.Name = .aqua) throws -> NSBitmapImageRep {
        let height = fittedHeight(view)
        let w = width * scale, h = height * scale
        let hosting = NSHostingView(rootView: view.frame(width: width, height: height, alignment: .top).scaleEffect(scale, anchor: .topLeading)
            .frame(width: w, height: h, alignment: .topLeading))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(x: 0, y: 0, width: w, height: h)
        hosting.wantsLayer = true
        spin(hosting)
        func sharpen(_ layer: CALayer) {
            layer.contentsScale = scale
            layer.shouldRasterize = false
            layer.sublayers?.forEach(sharpen)
            layer.setNeedsDisplay()
        }
        func sharpenViews(_ view: NSView) {
            view.wantsLayer = true
            if let layer = view.layer { sharpen(layer) }
            view.subviews.forEach(sharpenViews)
            view.needsDisplay = true
            view.displayIfNeeded()
        }
        sharpenViews(hosting)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = NSSize(width: w, height: h)
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }
}
