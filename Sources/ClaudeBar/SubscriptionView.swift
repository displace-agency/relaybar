import SwiftUI

struct SubscriptionView: View {
    var accounts: [SubscriptionAccount] = [.defaultClaude, .codexAccount]
    let subscriptions: [String: SubscriptionUsage]
    let isLoading: Bool
    @Environment(\.subscriptionPreviewDate) private var previewDate

    var body: some View {
        if let previewDate {
            content(now: previewDate)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                accountSection(account, name: Self.accountName(accounts, index), numbered: multipleClaude && account.provider == .claude, now: now)
            }
            Text("Codex limits apply to Codex usage on your ChatGPT plan. Local token totals are separate activity records.")
                .dsCaption()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var multipleClaude: Bool { accounts.filter { $0.provider == .claude }.count > 1 }

    /// "Claude", "Claude 2" (with several Claude accounts) or "Codex".
    static func accountName(_ accounts: [SubscriptionAccount], _ index: Int) -> String {
        let account = accounts[index]
        guard account.provider == .claude, accounts.filter({ $0.provider == .claude }).count > 1 else { return account.provider.title }
        return "Claude \(accounts[...index].filter { $0.provider == .claude }.count)"
    }

    private func accountSection(_ account: SubscriptionAccount, name: String, numbered: Bool, now: Date) -> some View {
        let usage = subscriptions[account.id]
        let hasReading = usage?.weekly != nil || usage?.session != nil
        return VStack(alignment: .leading, spacing: DS.Spacing.s) {
            if let weekly = usage?.weekly {
                limitCard(name: name, title: "Weekly", quota: weekly, account: account, usage: usage, showsAccount: numbered, now: now)
            } else {
                unavailableCard(name: name, account: account, usage: usage, showsAccount: numbered)
            }
            if let session = usage?.session {
                limitCard(name: name, title: session.durationMinutes == 300 ? "5-hour" : "Session", quota: session,
                          account: account, usage: nil, showsAccount: false, now: now)
            }
            if let error = usage?.error {
                DSNotice(title: hasReading ? "Last known reading" : "Needs attention", message: error)
            } else if let usage, now.timeIntervalSince(usage.fetchedAt) > 180 {
                DSNotice(title: "Reading is out of date", message: "Last reading is over 3 minutes old. Refresh to check current limits.")
            } else if usage == nil && !isLoading {
                Text("Refresh to read this subscription.").dsCaption()
            }
        }
    }

    private func cardHeader(_ eyebrow: String, account: SubscriptionAccount, usage: SubscriptionUsage?, showsAccount: Bool) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Text(eyebrow).dsEyebrow().lineLimit(1)
            Spacer(minLength: DS.Spacing.s)
            if showsAccount {
                Text(account.label).dsCaption().lineLimit(1).truncationMode(.middle)
            }
            if let plan = usage?.plan, !plan.isEmpty {
                Text(plan).dsCaption().lineLimit(1)
            }
        }
    }

    private func unavailableCard(name: String, account: SubscriptionAccount, usage: SubscriptionUsage?, showsAccount: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            cardHeader("\(name) \u{00B7} Weekly", account: account, usage: usage, showsAccount: showsAccount)
            Text(isLoading && usage == nil ? "Reading weekly limits\u{2026}" : "Weekly limit unavailable")
                .font(DS.bodyFont).foregroundColor(DS.inkSecondary)
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private func limitCard(name: String, title: String, quota: SubscriptionWindow, account: SubscriptionAccount,
                           usage: SubscriptionUsage?, showsAccount: Bool, now: Date) -> some View {
        let remaining = min(100, max(0, 100 - quota.usedPercent))
        let expired = quota.resetsAt.map { $0 <= now } ?? false
        let reached = !expired && remaining < 0.5
        let low = !expired && !reached && remaining < 20
        return VStack(alignment: .leading, spacing: DS.Spacing.s) {
            cardHeader("\(name) \u{00B7} \(title)", account: account, usage: usage, showsAccount: showsAccount)
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(String(format: "%.0f%%", remaining))
                    .font(DS.bigNumber(28))
                    .foregroundColor(expired ? DS.inkSecondary : reached ? DS.danger : DS.ink)
                Text("left").dsCaption()
                Spacer(minLength: DS.Spacing.s)
                if expired { DSPill(style: .outline, label: "Reset due") }
                else if reached { DSPill(style: .reached, label: "Limit reached") }
                else if low { DSPill(style: .low, label: "Low") }
            }
            DSProgressBar(remaining: remaining, muted: expired)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title): \(Int(remaining)) percent left")
            if let reset = quota.resetsAt {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                    Text(expired ? "Reset due \u{00B7} refresh to verify" : "Resets in \(quota.countdown(at: now))")
                        .font(DS.bodyMedium).monospacedDigit().foregroundColor(DS.ink)
                    Spacer(minLength: DS.Spacing.s)
                    Text(reset.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .dsCaption().lineLimit(1)
                }
                .help("Reset time in \(TimeZone.current.identifier)")
            } else {
                Text("Reset time unavailable").dsCaption()
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

private struct SubscriptionPreviewDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// A fixed date makes offscreen fixture renders deterministic; production uses TimelineView.
    var subscriptionPreviewDate: Date? {
        get { self[SubscriptionPreviewDateKey.self] }
        set { self[SubscriptionPreviewDateKey.self] = newValue }
    }
}
