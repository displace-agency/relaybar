import Foundation
import SwiftUI

final class UsageMonitor: ObservableObject {
    @Published var snapshot: UsageSnapshot = .empty
    @Published var selectedProvider: SubscriptionProvider = .claude {
        didSet { snapshot = snapshots[selectedProvider] ?? .empty }
    }
    @Published var accounts: [SubscriptionAccount] = [.defaultClaude, .codexAccount]
    @Published var subscriptions: [String: SubscriptionUsage] = [:]
    @Published var menuBarText: String = "◐ …"
    @Published var menuBarSegments: [MenuBarSegment] = []
    @Published var lastUpdated: Date?
    @Published var lastError: String?
    @Published var isLoading = false

    enum MenuBarTint { case neutral, amber, red }
    struct MenuBarSegment: Equatable { let text: String; let tint: MenuBarTint }

    private var snapshots: [SubscriptionProvider: UsageSnapshot] = [:]
    private var timer: Timer?
    private let workQueue = DispatchQueue(label: "agency.displace.ClaudeBar.fetch", qos: .utility)
    private let quotaService = SubscriptionUsageService()
    private var localInflight = false
    private var quotaInflight = false
    private var quotaTask: Task<Void, Never>?
    private var lastQuotaAttempt: Date?

    init(startAutomatically: Bool = true) {
        guard startAutomatically else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { timer?.invalidate(); quotaTask?.cancel() }

    func refresh() {
        // Claim the work on the main queue before enqueueing it. The previous
        // implementation guarded only its UI update, so repeated clicks queued scans.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        refreshMenuBar()
        if !localInflight {
            localInflight = true
            updateLoading()
            workQueue.async { [weak self] in
                let claude = TranscriptParser.shared.snapshot()
                let codex = CodexTranscriptParser.shared.snapshot()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.snapshots = [.claude: claude, .codex: codex]
                    self.snapshot = self.snapshots[self.selectedProvider] ?? .empty
                    self.lastUpdated = Date()
                    self.localInflight = false
                    self.updateLoading()
                    self.refreshMenuBar()
                }
            }
        }
        // Opening the popover also calls refresh; do not turn clicks into quota traffic.
        if !quotaInflight, lastQuotaAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true {
            quotaInflight = true
            lastQuotaAttempt = Date()
            updateLoading()
            quotaTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let service = self.quotaService
                let accounts = await Task.detached { service.discoverAccounts() }.value
                let results = await withTaskGroup(of: SubscriptionUsage.self) { group in
                    for account in accounts { group.addTask { await service.fetch(account) } }
                    var out: [SubscriptionUsage] = []
                    for await usage in group { out.append(usage) }
                    return out
                }
                guard !Task.isCancelled else { return }
                self.accounts = accounts
                for result in results {
                    self.subscriptions[result.key] = Self.retainingLastKnown(result, previous: self.subscriptions[result.key])
                }
                let live = Set(accounts.map(\.id))
                self.subscriptions = self.subscriptions.filter { live.contains($0.key) }
                self.quotaInflight = false
                self.updateLoading()
                self.refreshMenuBar()
            }
        }
    }

    static func retainingLastKnown(_ result: SubscriptionUsage, previous: SubscriptionUsage?) -> SubscriptionUsage {
        guard result.error != nil, let previous, previous.weekly != nil || previous.session != nil else { return result }
        return SubscriptionUsage(provider: result.provider, weekly: previous.weekly, session: previous.session,
                                 fetchedAt: previous.fetchedAt, error: result.error, plan: previous.plan,
                                 accountID: result.accountID, label: result.label)
    }

    private func updateLoading() { isLoading = localInflight || quotaInflight }

    /// `C` for a single Claude account, `C1`, `C2`, ... for two or more; `O` for Codex.
    static func menuBarText(accounts: [SubscriptionAccount], subscriptions: [String: SubscriptionUsage], now: Date = Date()) -> String {
        let pieces = menuBarSegments(accounts: accounts, subscriptions: subscriptions, now: now).map(\.text)
        return pieces.isEmpty ? "◐ Quota" : "◐ " + pieces.joined(separator: "  ")
    }

    /// One compact reading per account. Low accounts get a tint; the text itself stays plain.
    static func menuBarSegments(accounts: [SubscriptionAccount], subscriptions: [String: SubscriptionUsage], now: Date = Date()) -> [MenuBarSegment] {
        let claudeCount = accounts.filter { $0.provider == .claude }.count
        var claudeIndex = 0
        return accounts.compactMap { account -> MenuBarSegment? in
            var name = "O"
            if account.provider == .claude {
                claudeIndex += 1
                name = claudeCount > 1 ? "C\(claudeIndex)" : "C"
            }
            guard let usage = subscriptions[account.id], let weekly = usage.weekly else { return nil }
            let stale = usage.error != nil || now.timeIntervalSince(usage.fetchedAt) > 180
            let countdown: String
            var live = false
            if let reset = weekly.resetsAt, reset > now, reset.timeIntervalSince(now) < 31_557_600 {
                let minutes = Int(ceil(reset.timeIntervalSince(now) / 60))
                countdown = minutes >= 1440 ? "\(minutes / 1440)d" : minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m"
                live = !stale
            } else {
                countdown = weekly.resetsAt == nil ? "?" : "due"
            }
            let tint: MenuBarTint = !live ? .neutral : weekly.usedPercent >= 90 ? .red : weekly.usedPercent >= 70 ? .amber : .neutral
            return MenuBarSegment(text: "\(name)\u{2009}\(stale ? "~" : "")\(countdown)", tint: tint)
        }
    }

    private func refreshMenuBar() {
        menuBarSegments = Self.menuBarSegments(accounts: accounts, subscriptions: subscriptions)
        menuBarText = Self.menuBarText(accounts: accounts, subscriptions: subscriptions)
    }
}
