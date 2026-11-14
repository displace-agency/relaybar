import XCTest
import SwiftUI
import AppKit
import Vision
@testable import ClaudeBar

/// Opt-in, read-only capture of real subscriptions and aggregate local usage.
/// Never capture sessions or other views containing projects or conversation data.
final class MarketingCaptureTests: XCTestCase {
    @MainActor
    func testCaptureLiveMarketingScreenshots() async throws {
        guard ProcessInfo.processInfo.environment["RELAYBAR_MARKETING_CAPTURE"] == "1" else {
            throw XCTSkip("Set RELAYBAR_MARKETING_CAPTURE=1 to capture live account data offscreen.")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("docs/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let service = SubscriptionUsageService()
        let discovered = service.discoverAccounts()
        var reads: [String: SubscriptionUsage] = [:]
        await withTaskGroup(of: (String, SubscriptionUsage).self) { group in
            for account in discovered { group.addTask { (account.id, await service.fetch(account)) } }
            for await (id, usage) in group { reads[id] = usage }
        }
        // Privacy: replace every account label (an email address) with a neutral one, in the capture only.
        var claudeNumber = 0
        let accounts: [SubscriptionAccount] = discovered.map { account in
            guard account.provider == .claude else { return account }
            claudeNumber += 1
            return SubscriptionAccount(id: account.id, provider: .claude, label: "Account \(claudeNumber)", profile: account.profile)
        }
        var subscriptions: [String: SubscriptionUsage] = [:]
        for account in accounts {
            var usage = try XCTUnwrap(reads[account.id])
            XCTAssertNil(usage.error, usage.error ?? "")
            _ = try XCTUnwrap(usage.weekly, "no real weekly reading for \(account.label)")
            usage.label = account.label
            subscriptions[account.id] = usage
        }
        let now = Date()
        let monitor = UsageMonitor(startAutomatically: false)
        monitor.accounts = accounts
        monitor.subscriptions = subscriptions
        monitor.lastUpdated = now
        for (name, scheme) in [("quota-limits-light", ColorScheme.light), ("quota-limits-dark", .dark)] {
            let bitmap = try render(MenuView(monitor: monitor), scheme: scheme, now: now)
            let recognized = try text(in: bitmap)
            XCTAssertTrue(recognized.contains("Claude"))
            XCTAssertTrue(recognized.contains("Codex"))
            XCTAssertFalse(recognized.contains("@"))
            XCTAssertGreaterThanOrEqual(recognized.components(separatedBy: "% remaining").count - 1, 2)
            XCTAssertGreaterThanOrEqual(recognized.components(separatedBy: "Resets in").count - 1, 2)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        }
        let segments = UsageMonitor.menuBarSegments(accounts: accounts, subscriptions: subscriptions, now: now)
        XCTAssertFalse(segments.isEmpty)
        try XCTUnwrap(renderMenuBarLabel(segments).representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("quota-menubar-label.png"))
        monitor.selectedProvider = .codex
        monitor.snapshot = CodexTranscriptParser().snapshot()
        let bitmap = try render(MenuView(monitor: monitor, initialTab: .overview), scheme: .light, now: now)
        let recognized = try text(in: bitmap)
        XCTAssertTrue(recognized.contains("Codex"))
        XCTAssertTrue(recognized.lowercased().contains("tokens"))
        XCTAssertFalse(recognized.contains("$"))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("quota-overview-light.png"))
        if let manifestDirectory = ProcessInfo.processInfo.environment["RELAYBAR_CAPTURE_MANIFEST_DIR"] {
            let provenance = "Live Quota marketing captures\nCaptured: \(ISO8601DateFormatter().string(from: now))\nLimits use actual authenticated subscription GET responses. Overview uses actual local aggregate Codex token activity. No synthetic values, sessions, project names, account identifiers, or desktop pixels. Offscreen NSHostingView rendered at 3x.\n"
            try Data(provenance.utf8).write(to: URL(fileURLWithPath: manifestDirectory).appendingPathComponent("CAPTURE-PROVENANCE.txt"))
        }
    }

    @MainActor
    func testCaptureLiveCodexOverview() throws {
        guard ProcessInfo.processInfo.environment["RELAYBAR_MARKETING_CAPTURE"] == "overview" else {
            throw XCTSkip("Set RELAYBAR_MARKETING_CAPTURE=overview to refresh only the local Codex overview.")
        }
        let monitor = UsageMonitor(startAutomatically: false)
        monitor.selectedProvider = .codex
        monitor.snapshot = CodexTranscriptParser().snapshot()
        let now = Date()
        monitor.lastUpdated = now
        let bitmap = try render(MenuView(monitor: monitor, initialTab: .overview), scheme: .light, now: now)
        let recognized = try text(in: bitmap)
        XCTAssertTrue(recognized.contains("Codex"))
        XCTAssertTrue(recognized.lowercased().contains("tokens"))
        XCTAssertFalse(recognized.contains("$"))
        XCTAssertFalse(recognized.contains("No activity"))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("docs/screenshots/quota-overview-light.png"))
        if let manifestDirectory = ProcessInfo.processInfo.environment["RELAYBAR_CAPTURE_MANIFEST_DIR"] {
            try Data("Codex overview refreshed from live local aggregate activity: \(ISO8601DateFormatter().string(from: now))\nNo project names, session lists, conversations or account identifiers.\n".utf8)
                .write(to: URL(fileURLWithPath: manifestDirectory).appendingPathComponent("OVERVIEW-PROVENANCE.txt"))
        }
    }

    /// Same drawing as the app's status item (ClaudeBarApp.renderBarImage), at 3x on a light bar.
    private func renderMenuBarLabel(_ segments: [UsageMonitor.MenuBarSegment]) throws -> NSBitmapImageRep {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        let dotFont = NSFont.systemFont(ofSize: 7)
        let attr = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { attr.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            if segment.tint != .neutral {
                let dot: NSColor = segment.tint == .red ? .systemRed : .systemOrange
                attr.append(NSAttributedString(string: "\u{25CF}\u{2009}", attributes: [.font: dotFont, .foregroundColor: dot, .baselineOffset: 1.5]))
            }
            attr.append(NSAttributedString(string: segment.text, attributes: [.font: font, .foregroundColor: NSColor(white: 0.1, alpha: 1)]))
        }
        let textSize = attr.size()
        let pad: CGFloat = 10, height: CGFloat = 24, scale: CGFloat = 3
        let size = NSSize(width: ceil(textSize.width) + pad * 2, height: height)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(white: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
        attr.draw(at: NSPoint(x: pad, y: (height - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func text(in bitmap: NSBitmapImageRep) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    @MainActor
    private func render<V: View>(_ view: V, scheme: ColorScheme, now: Date) throws -> NSBitmapImageRep {
        let root = view.environment(\.subscriptionPreviewDate, now)
            .environment(\.colorScheme, scheme)
            .tint(Color.blue)
            .accentColor(.blue)
            .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
        let hosting = NSHostingView(rootView: root.scaleEffect(3, anchor: .topLeading)
            .frame(width: 1260, height: 1560, alignment: .topLeading))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 1260, height: 1560)
        hosting.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()
        func sharpen(_ layer: CALayer) {
            layer.contentsScale = 3
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
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1260, pixelsHigh: 1560,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = NSSize(width: 1260, height: 1560)
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }
}
