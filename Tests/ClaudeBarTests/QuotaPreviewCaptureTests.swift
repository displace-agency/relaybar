import XCTest
import SwiftUI
import AppKit
@testable import ClaudeBar

/// Design-iteration renders from plainly fake numbers. Skipped unless QUOTA_PREVIEW_CAPTURE=1.
/// Output goes to QUOTA_PREVIEW_DIR. These are for checking layout only, never marketing shots.
final class QuotaPreviewCaptureTests: XCTestCase {
    private let scale: CGFloat = 2

    @MainActor
    func testRenderPreviewFixtures() throws {
        guard ProcessInfo.processInfo.environment["QUOTA_PREVIEW_CAPTURE"] == "1",
              let directory = ProcessInfo.processInfo.environment["QUOTA_PREVIEW_DIR"] else {
            throw XCTSkip("Set QUOTA_PREVIEW_CAPTURE=1 and QUOTA_PREVIEW_DIR to render fake-data previews.")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date()

        func usage(_ provider: SubscriptionProvider, weekly: Double?, session: Double?, error: String? = nil, plan: String? = nil,
                   resetDays: Double = 3.3, id: String? = nil, label: String? = nil) -> SubscriptionUsage {
            SubscriptionUsage(provider: provider,
                weekly: weekly.map { SubscriptionWindow(usedPercent: $0, resetsAt: now.addingTimeInterval(resetDays * 86400), durationMinutes: 10080) },
                session: session.map { SubscriptionWindow(usedPercent: $0, resetsAt: now.addingTimeInterval(2.4 * 3600), durationMinutes: 300) },
                fetchedAt: now, error: error, plan: plan, accountID: id, label: label)
        }

        // 1. Two providers, healthy.
        let monitor = UsageMonitor(startAutomatically: false)
        monitor.subscriptions = [
            "claude": usage(.claude, weekly: 37, session: 18, plan: "Max"),
            "codex": usage(.codex, weekly: 76, session: 29, plan: "Pro", resetDays: 1.2)
        ]
        monitor.lastUpdated = now
        try save(MenuView(monitor: monitor), "01-limits", now, output)

        // 2. Several Claude accounts: low, limit reached, expired reset, error with last reading.
        let a1 = SubscriptionAccount(id: "c1", provider: .claude, label: "demo.one@example.com", profile: nil)
        let a2 = SubscriptionAccount(id: "c2", provider: .claude, label: "demo.two@example.com", profile: nil)
        let multi = UsageMonitor(startAutomatically: false)
        multi.accounts = [a1, a2, .codexAccount]
        multi.subscriptions = [
            "c1": usage(.claude, weekly: 88, session: 100, plan: "Max", id: "c1", label: a1.label),
            "c2": usage(.claude, weekly: 100, session: 40, error: "Usage checks are rate limited. Try again later.", plan: "Pro", id: "c2", label: a2.label),
            "codex": usage(.codex, weekly: 50, session: nil, resetDays: -0.1)
        ]
        multi.lastUpdated = now
        try save(MenuView(monitor: multi), "02-limits-states", now, output)

        // 3. Nothing readable.
        let none = UsageMonitor(startAutomatically: false)
        none.subscriptions = ["claude": usage(.claude, weekly: nil, session: nil, error: "Session expired or access denied. Open the CLI to reconnect.")]
        try save(MenuView(monitor: none), "03-limits-unavailable", now, output)

        // 4. Local activity tabs with fake data.
        let local = UsageMonitor(startAutomatically: false)
        local.subscriptions = monitor.subscriptions
        local.lastUpdated = now
        local.selectedProvider = .claude
        local.snapshot = Self.fakeSnapshot(now: now)
        try save(MenuView(monitor: local, initialTab: .overview), "04-overview", now, output)
        try save(MenuView(monitor: local, initialTab: .sessions), "05-sessions", now, output)
        try save(MenuView(monitor: local, initialTab: .history), "06-history", now, output)
        local.selectedProvider = .codex
        local.snapshot = Self.fakeSnapshot(now: now)
        try save(MenuView(monitor: local, initialTab: .overview), "07-overview-codex", now, output)

        // 5. Menu bar label (unchanged drawing, light bar).
        let segments = UsageMonitor.menuBarSegments(accounts: [.defaultClaude, .codexAccount], subscriptions: monitor.subscriptions, now: now)
        XCTAssertFalse(segments.isEmpty)
        try label(segments).representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("08-menubar-label.png"))
        try Data("Disposable Quota design previews. Synthetic fake numbers only. Not marketing material.\n".utf8)
            .write(to: output.appendingPathComponent("MANIFEST.txt"))
    }

    private static func fakeSnapshot(now: Date) -> UsageSnapshot {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let daily: [DailyEntry] = (0..<45).map { i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: now)!
            let base = 120_000 + ((i * 7919) % 11) * 90_000
            return DailyEntry(date: fmt.string(from: d), tokens: TokenCounts(inputTokens: base, outputTokens: base / 3),
                              costUSD: Double(base) / 30_000, models: ["claude-sonnet-4"])
        }
        var sessions: [SessionEntry] = []
        for i in 0..<9 {
            let age = Double(i) * 7200
            let tokens = TokenCounts(inputTokens: 40_000 + i * 15_000, outputTokens: 9_000 + i * 2_000)
            let model = i % 2 == 0 ? "claude-sonnet-4" : "claude-opus-4"
            sessions.append(SessionEntry(sessionId: "demo-\(i)", projectPath: "/Users/demo/projects/demo-project-\(i)", inferredProject: nil,
                                         startTime: now.addingTimeInterval(-age - 1800), lastActivity: now.addingTimeInterval(-age),
                                         tokens: tokens, costUSD: 1.5 + Double(i), models: [model], messageCount: 12 + i * 5))
        }
        let today = DailyEntry(date: fmt.string(from: now),
                               tokens: TokenCounts(inputTokens: 412_000, outputTokens: 96_000, cacheCreationInputTokens: 210_000, cacheReadInputTokens: 3_400_000),
                               costUSD: 12.34, models: ["claude-sonnet-4", "claude-opus-4"])
        let block = UsageBlock(id: "b", startTime: now.addingTimeInterval(-3600), endTime: now.addingTimeInterval(4 * 3600), lastActivity: now,
                               isActive: true, tokens: TokenCounts(inputTokens: 180_000, outputTokens: 44_000), costUSD: 4.2, models: [],
                               burnRate: BurnRate(tokensPerMinute: 3_700, costPerHour: 4.1),
                               projection: Projection(totalCost: 9.9, totalTokens: 1_150_000, remainingMinutes: 240))
        let models = [
            ModelUsage(model: "claude-sonnet-4", tokens: TokenCounts(inputTokens: 300_000, outputTokens: 70_000), costUSD: 6.1),
            ModelUsage(model: "claude-opus-4", tokens: TokenCounts(inputTokens: 112_000, outputTokens: 26_000), costUSD: 6.2),
            ModelUsage(model: "claude-haiku-3", tokens: TokenCounts(inputTokens: 30_000, outputTokens: 8_000), costUSD: 0.1)
        ]
        return UsageSnapshot(activeBlock: block, today: today, daily: daily, sessions: sessions, modelsToday: models,
                             last7DaysCost: 80, last30DaysCost: 300, last30DaysTokens: 30_000_000, monthCost: 300,
                             allTimeTokens: 98_400_000, allTimeCost: 1234, activeDays: 45,
                             firstActiveDate: fmt.string(from: Calendar.current.date(byAdding: .day, value: -44, to: now)!))
    }

    @MainActor
    private func save<V: View>(_ view: V, _ name: String, _ now: Date, _ output: URL) throws {
        let w = 420 * scale, h = 520 * scale
        let root = view.environment(\.subscriptionPreviewDate, now)
            .environment(\.colorScheme, .dark) // MenuView must force light itself
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: w, height: h, alignment: .topLeading)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: w, height: h)
        hosting.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = NSSize(width: w, height: h)
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
    }

    private func label(_ segments: [UsageMonitor.MenuBarSegment]) throws -> NSBitmapImageRep {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        let attr = NSMutableAttributedString()
        for (i, s) in segments.enumerated() {
            if i > 0 { attr.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            attr.append(NSAttributedString(string: s.text, attributes: [.font: font, .foregroundColor: NSColor(white: 0.1, alpha: 1)]))
        }
        let t = attr.size(), pad: CGFloat = 10, height: CGFloat = 24, k: CGFloat = 8
        let size = NSSize(width: ceil(t.width) + pad * 2, height: height)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * k), pixelsHigh: Int(height * k),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(white: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
        attr.draw(at: NSPoint(x: pad, y: (height - t.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
