import XCTest
@testable import ClaudeBar

final class UsageMonitorTests: XCTestCase {
    func testFailureRetainsOriginalReadingAndTimestamp() {
        let date = Date(timeIntervalSince1970: 100)
        let window = SubscriptionWindow(usedPercent: 75, resetsAt: date.addingTimeInterval(10080 * 60), durationMinutes: 10080)
        let old = SubscriptionUsage(provider: .claude, weekly: window, session: nil, fetchedAt: date, error: nil, plan: "max")
        let failed = SubscriptionUsage(provider: .claude, weekly: nil, session: nil, fetchedAt: Date(), error: "Offline", plan: nil)
        let retained = UsageMonitor.retainingLastKnown(failed, previous: old)
        XCTAssertEqual(retained.weekly?.usedPercent, 75)
        XCTAssertEqual(retained.fetchedAt, date)
        XCTAssertEqual(retained.error, "Offline")
        XCTAssertEqual(retained.plan, "max")
    }

    func testRecoveryReplacesPreviousUsageAndClearsError() {
        let old = SubscriptionUsage(provider: .codex, weekly: nil, session: nil, fetchedAt: .distantPast, error: "Offline", plan: nil)
        let date = Date()
        let fresh = SubscriptionUsage(provider: .codex, weekly: SubscriptionWindow(usedPercent: 0, resetsAt: date, durationMinutes: 10080), session: nil, fetchedAt: date, error: nil, plan: "pro")
        let result = UsageMonitor.retainingLastKnown(fresh, previous: old)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.weekly?.usedPercent, 0)
        XCTAssertEqual(result.fetchedAt, date)
    }

    private func usage(_ id: String, provider: SubscriptionProvider, reset: TimeInterval, now: Date) -> SubscriptionUsage {
        SubscriptionUsage(provider: provider, weekly: SubscriptionWindow(usedPercent: 10, resetsAt: now.addingTimeInterval(reset), durationMinutes: 10080),
                          session: nil, fetchedAt: now, error: nil, plan: nil, accountID: id)
    }

    private func account(_ id: String, _ provider: SubscriptionProvider) -> SubscriptionAccount {
        SubscriptionAccount(id: id, provider: provider, label: id, profile: nil)
    }

    func testMenuBarLabelKeepsPlainCForOneClaudeAccount() {
        let now = Date()
        let text = UsageMonitor.menuBarText(
            accounts: [account("claude", .claude), .codexAccount],
            subscriptions: ["claude": usage("claude", provider: .claude, reset: 3 * 86400 + 3600, now: now),
                            "codex": usage("codex", provider: .codex, reset: 2 * 3600 + 60, now: now)], now: now)
        XCTAssertEqual(text, "◐ C\u{2009}3d  O\u{2009}2h")
    }

    func testMenuBarLabelNumbersClaudeAccountsWhenTwoOrMore() {
        let now = Date()
        let text = UsageMonitor.menuBarText(
            accounts: [account("claude", .claude), account("claude:/h/.claude-2", .claude), .codexAccount],
            subscriptions: ["claude": usage("claude", provider: .claude, reset: 3 * 86400 + 3600, now: now),
                            "claude:/h/.claude-2": usage("x", provider: .claude, reset: 86400 + 3600, now: now),
                            "codex": usage("codex", provider: .codex, reset: 2 * 3600 + 60, now: now)], now: now)
        XCTAssertEqual(text, "◐ C1\u{2009}3d  C2\u{2009}1d  O\u{2009}2h")
    }

    func testMenuBarLabelMarksStaleAndFallsBackWhenEmpty() {
        let now = Date()
        var old = usage("claude", provider: .claude, reset: 3600, now: now)
        old = SubscriptionUsage(provider: .claude, weekly: old.weekly, session: nil, fetchedAt: now.addingTimeInterval(-600), error: nil, plan: nil, accountID: "claude")
        XCTAssertEqual(UsageMonitor.menuBarText(accounts: [account("claude", .claude)], subscriptions: ["claude": old], now: now), "◐ C\u{2009}~1h")
        XCTAssertEqual(UsageMonitor.menuBarText(accounts: [account("claude", .claude)], subscriptions: [:], now: now), "◐ Quota")
    }

    func testMenuBarTintsOnlyLowAccountsAndKeepsTextPlain() {
        let now = Date()
        func reading(_ used: Double) -> SubscriptionUsage {
            SubscriptionUsage(provider: .claude, weekly: SubscriptionWindow(usedPercent: used, resetsAt: now.addingTimeInterval(7200), durationMinutes: 10080),
                              session: nil, fetchedAt: now, error: nil, plan: nil, accountID: "x")
        }
        let segments = UsageMonitor.menuBarSegments(
            accounts: [account("a", .claude), account("b", .claude), account("c", .claude)],
            subscriptions: ["a": reading(97), "b": reading(75), "c": reading(1)], now: now)
        XCTAssertEqual(segments.map(\.tint), [.red, .amber, .neutral])
        XCTAssertEqual(segments.map(\.text), ["C1\u{2009}2h", "C2\u{2009}2h", "C3\u{2009}2h"])
    }
}
