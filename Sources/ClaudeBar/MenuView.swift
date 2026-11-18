import SwiftUI
import ServiceManagement

struct MenuView: View {
    @ObservedObject var monitor: UsageMonitor
    @State private var selectedTab: Tab = .limits
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    enum Tab: String, CaseIterable, Identifiable {
        case limits = "Limits"
        case overview = "Overview"
        case sessions = "Sessions"
        case history = "History"
        var id: String { rawValue }
    }

    init(monitor: UsageMonitor, initialTab: Tab = .limits) {
        self.monitor = monitor
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    if selectedTab != .limits {
                        DSSegmented(options: [(SubscriptionProvider.claude, "Claude"), (.codex, "Codex")],
                                    selection: $monitor.selectedProvider)
                        Text("Local activity \u{00B7} input + output tokens, excluding cache tokens.")
                            .dsCaption()
                    }
                    switch selectedTab {
                    case .limits: SubscriptionView(accounts: monitor.accounts, subscriptions: monitor.subscriptions, isLoading: monitor.isLoading)
                    case .overview: OverviewTab(snapshot: monitor.snapshot)
                    case .sessions: SessionsTab(snapshot: monitor.snapshot)
                    case .history: HistoryTab(snapshot: monitor.snapshot)
                    }
                }
                .environment(\.showsAPICost, monitor.selectedProvider == .claude)
                .padding(DS.Spacing.m)
            }
            .frame(maxHeight: .infinity)
            .background(DS.canvas)
            DSHairline()
            footer
        }
        .frame(width: DS.Layout.popover.width, height: DS.Layout.popover.height)
        .background(DS.surface)
        // The brand look is light in both macOS appearances.
        .environment(\.colorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quota").dsTitle()
                Text(headline).dsCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if monitor.isLoading {
                Text("Refreshing\u{2026}").dsCaption()
            } else if let updated = monitor.lastUpdated ?? monitor.subscriptions.values.map(\.fetchedAt).max() {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").dsCaption()
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.top, DS.Spacing.m)
        .padding(.bottom, DS.Spacing.s)
        .background(DS.surface)
    }

    /// One caption sentence with the most important fact: the weekly limit with the least left.
    private var headline: String {
        let now = Date()
        var lowest: (name: String, remaining: Double)?
        for (index, account) in monitor.accounts.enumerated() {
            guard let weekly = monitor.subscriptions[account.id]?.weekly else { continue }
            if let reset = weekly.resetsAt, reset <= now { continue }
            let remaining = min(100, max(0, 100 - weekly.usedPercent))
            if lowest == nil || remaining < lowest!.remaining {
                lowest = (SubscriptionView.accountName(monitor.accounts, index), remaining)
            }
        }
        guard let lowest else { return "Claude + Codex \u{00B7} subscription limits & local activity" }
        if lowest.remaining < 0.5 { return "\(lowest.name): weekly limit reached." }
        return String(format: "%@: %.0f%% of the weekly limit left.", lowest.name, lowest.remaining)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: DS.Spacing.l) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { index, tab in
                let on = selectedTab == tab
                Button {
                    withAnimation(DS.Motion.quick) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(on ? DS.ink : DS.inkSecondary)
                        .padding(.vertical, DS.Spacing.s)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(on ? DS.ink : Color.clear).frame(height: 1.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.m)
        .background(DS.surface)
        .overlay(alignment: .bottom) { DSHairline() }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: DS.Spacing.s) {
            Button(monitor.isLoading ? "Refreshing\u{2026}" : "Refresh") { monitor.refresh() }
                .buttonStyle(.dsSecondarySmall)
                .disabled(monitor.isLoading)
                .help("Refresh subscription limits and local token activity")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.dsSecondarySmall)
                .keyboardShortcut("q")
            Button {
                launchAtLogin.toggle()
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(launchAtLogin ? DS.ink : DS.surface)
                        .frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(launchAtLogin ? DS.ink : DS.border, lineWidth: 1))
                        .overlay {
                            if launchAtLogin {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                            }
                        }
                    Text("Launch at login").font(DS.captionFont).foregroundColor(DS.ink)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, DS.Spacing.xs)
            .accessibilityAddTraits(launchAtLogin ? .isSelected : [])
            .onChange(of: launchAtLogin) { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
            Spacer(minLength: 0)
            Text("By Displace").dsEyebrow()
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .background(DS.surface)
    }
}

// MARK: - Shared pieces

private struct SectionCard<Content: View>: View {
    let eyebrow: String
    var trailing: String? = nil
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow).dsEyebrow()
                Spacer(minLength: DS.Spacing.s)
                if let trailing { Text(trailing).dsCaption() }
            }
            if let note { Text(note).dsCaption().fixedSize(horizontal: false, vertical: true) }
            content
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

private struct EmptyLine: View {
    let text: String
    var body: some View { Text(text).font(DS.bodyFont).foregroundColor(DS.inkSecondary) }
}

/// Ink bar on a hairline track.
private struct InkBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(DS.hairline)
                RoundedRectangle(cornerRadius: 2).fill(DS.ink)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Overview

private struct OverviewTab: View {
    @Environment(\.showsAPICost) private var showsAPICost
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            todayBlock
            if showsAPICost { activeBlock }
            modelsBlock
        }
    }

    private var todayBlock: some View {
        SectionCard(eyebrow: "Today \u{00B7} local token activity") {
            if let d = snapshot.today {
                HeroTokens(tokens: d.totalTokens, cost: d.costUSD)
                DSHairline()
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    Stat(label: "Input", value: formatTokens(d.tokens.inputTokens))
                    Stat(label: "Output", value: formatTokens(d.tokens.outputTokens))
                    Stat(label: "Cache write", value: formatTokens(d.tokens.cacheCreationInputTokens))
                    Stat(label: "Cache hits",
                         value: formatTokens(d.tokens.cacheHitTokens),
                         sub: String(format: "%.0f%% reuse", d.tokens.cacheHitRate * 100))
                }
            } else {
                EmptyLine(text: "No usage today yet")
            }
        }
    }

    private var activeBlock: some View {
        SectionCard(eyebrow: "Inferred 5-hour activity block",
                    note: "Estimated from local activity, independent of subscription resets.") {
            if let b = snapshot.activeBlock {
                HeroTokens(tokens: b.totalTokens, cost: b.costUSD)
                if let r = b.burnRate, let p = b.projection {
                    DSHairline()
                    HStack(alignment: .top, spacing: DS.Spacing.m) {
                        Stat(label: "Rate", value: "\(formatTokens(Int(r.tokensPerMinute)))/min")
                        Stat(label: "Block ends in", value: "\(p.remainingMinutes) min")
                        Stat(label: "Projected", value: formatTokens(p.totalTokens))
                    }
                }
            } else {
                EmptyLine(text: "No activity in the last 5 hours")
            }
        }
    }

    private var modelsBlock: some View {
        SectionCard(eyebrow: "Models today") {
            if snapshot.modelsToday.isEmpty {
                EmptyLine(text: "\u{2014}")
            } else {
                ModelBreakdownView(models: snapshot.modelsToday)
            }
        }
    }
}

// MARK: - Sessions

private struct SessionsTab: View {
    let snapshot: UsageSnapshot
    @State private var sortMode: SortMode = .recent

    enum SortMode: String, CaseIterable {
        case recent = "Recent"
        case biggest = "Biggest"
    }

    private var sortedSessions: [SessionEntry] {
        switch sortMode {
        case .recent: return snapshot.sessions
        case .biggest: return snapshot.sessions.sorted { $0.tokens.totalTokens > $1.tokens.totalTokens }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions").dsEyebrow()
                Spacer()
                Text("\(snapshot.sessions.count) total").dsCaption().monospacedDigit()
            }
            DSSegmented(options: SortMode.allCases.map { ($0, $0.rawValue) }, selection: $sortMode)
            if snapshot.sessions.isEmpty {
                EmptyLine(text: "No sessions found")
            } else {
                let rows = Array(sortedSessions.prefix(40))
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, s in
                        if index > 0 { DSHairline() }
                        SessionRow(session: s)
                    }
                }
                .dsCard()
            }
        }
    }
}

private struct SessionRow: View {
    @Environment(\.showsAPICost) private var showsAPICost
    let session: SessionEntry
    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .medium)).foregroundColor(DS.ink)
                        .lineLimit(1)
                    Text(session.projectPathShort)
                        .dsCaption()
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Text(session.lastActivity.formatted(.relative(presentation: .named)))
                    Text("\u{00B7}")
                    Text("\(session.messageCount) msg")
                    if let family = session.models.first.map(Pricing.family(for:)) {
                        Text("\u{00B7}")
                        Text(family)
                    }
                }
                .dsCaption().lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTokens(session.tokens.totalTokens))
                    .font(DS.bodyMedium).foregroundColor(DS.ink)
                    .monospacedDigit()
                if showsAPICost {
                    Text(String(format: "\u{2248} $%.2f", session.costUSD))
                        .dsCaption().monospacedDigit()
                }
            }
        }
        .padding(.vertical, DS.Spacing.s)
        .padding(.horizontal, DS.Spacing.m)
    }
}

// MARK: - History

private struct HistoryTab: View {
    @Environment(\.showsAPICost) private var showsAPICost
    let snapshot: UsageSnapshot

    private func recentDays(_ count: Int) -> [DailyEntry] {
        calendarDays(snapshot.daily, count: count)
    }

    private var last7DaysTokens: Int {
        recentDays(7).reduce(0) { $0 + $1.totalTokens }
    }

    private var weeklyBuckets: [(weekStart: Date, tokens: Int, cost: Double)] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.timeZone = TimeZone.current

        var buckets: [Date: (Int, Double)] = [:]
        for d in snapshot.daily {
            guard let date = inFmt.date(from: d.date),
                  let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start
            else { continue }
            var entry = buckets[weekStart] ?? (0, 0)
            entry.0 += d.totalTokens
            entry.1 += d.costUSD
            buckets[weekStart] = entry
        }
        return buckets
            .map { (weekStart: $0.key, tokens: $0.value.0, cost: $0.value.1) }
            .sorted { $0.weekStart > $1.weekStart }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            totalsCard
            weeklyCard
            dailyCard
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                TotalsColumn(label: "Last 7 days", tokens: last7DaysTokens, cost: recentDays(7).reduce(0) { $0 + $1.costUSD })
                Rectangle().fill(DS.hairline).frame(width: 1)
                TotalsColumn(label: "Last 30 days", tokens: recentDays(30).reduce(0) { $0 + $1.totalTokens }, cost: recentDays(30).reduce(0) { $0 + $1.costUSD })
                Rectangle().fill(DS.hairline).frame(width: 1)
                TotalsColumn(label: "All time", tokens: snapshot.allTimeTokens, cost: snapshot.allTimeCost)
            }
            if let sub = activeDaysSub {
                DSHairline()
                Text("All time \u{00B7} \(sub)").dsCaption()
                    .padding(.horizontal, DS.Spacing.m).padding(.vertical, DS.Spacing.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var weeklyCard: some View {
        SectionCard(eyebrow: "Weekly tokens (last 12)") {
            let weeks = Array(weeklyBuckets.prefix(12))
            if weeks.isEmpty {
                EmptyLine(text: "\u{2014}")
            } else {
                let maxTok = max(weeks.map(\.tokens).max() ?? 1, 1)
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { i in
                                DSHairline()
                                if i < 3 { Spacer(minLength: 0) }
                            }
                        }
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(weeks.reversed(), id: \.weekStart) { w in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(DS.ink)
                                    .frame(maxWidth: 22)
                                    .frame(height: max(2, CGFloat(Double(w.tokens) / Double(maxTok)) * 60))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(height: 60)
                    HStack(spacing: 4) {
                        ForEach(weeks.reversed(), id: \.weekStart) { w in
                            Text(weekLabel(w.weekStart))
                                .font(.system(size: 9)).foregroundColor(DS.inkSecondary)
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var dailyCard: some View {
        SectionCard(eyebrow: "Daily tokens (last 30)") {
            let recent = recentDays(30)
            if recent.isEmpty {
                EmptyLine(text: "\u{2014}")
            } else {
                let maxTok = max(recent.map(\.totalTokens).max() ?? 1, 1)
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, d in
                        if index > 0 { DSHairline() }
                        HStack(spacing: DS.Spacing.s) {
                            Text(shortDate(d.date))
                                .dsCaption()
                                .frame(width: 52, alignment: .leading).monospacedDigit()
                            InkBar(fraction: Double(d.totalTokens) / Double(maxTok))
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(formatTokens(d.totalTokens))
                                    .font(.system(size: 11, weight: .medium)).foregroundColor(DS.ink).monospacedDigit()
                                if showsAPICost {
                                    Text(String(format: "\u{2248} $%.0f", d.costUSD))
                                        .dsCaption().monospacedDigit()
                                }
                            }
                            .frame(width: 62, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private var activeDaysSub: String? {
        guard snapshot.activeDays > 0 else { return nil }
        if let first = snapshot.firstActiveDate {
            return "\(snapshot.activeDays) days \u{00B7} since \(shortMonthDay(first))"
        }
        return "\(snapshot.activeDays) active days"
    }

    private func shortMonthDay(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.timeZone = TimeZone.current
        guard let date = inFmt.date(from: iso) else { return iso }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "MMM d"
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        return outFmt.string(from: date)
    }

    private func weekLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }

    private func shortDate(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.timeZone = TimeZone.current
        guard let date = inFmt.date(from: iso) else { return iso }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "EEE d"
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        return outFmt.string(from: date)
    }
}

private struct HeroTokens: View {
    @Environment(\.showsAPICost) private var showsAPICost
    let tokens: Int
    let cost: Double
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Text(formatTokens(tokens))
                .font(DS.bigNumber(28)).foregroundColor(DS.ink)
            Text("tokens").dsCaption()
            Spacer()
            if showsAPICost {
                Text(String(format: "\u{2248} $%.2f API", cost))
                    .dsCaption().monospacedDigit()
            }
        }
    }
}

private struct TotalsColumn: View {
    @Environment(\.showsAPICost) private var showsAPICost
    let label: String
    let tokens: Int
    let cost: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).dsEyebrow().lineLimit(1).minimumScaleFactor(0.8)
            Text(formatTokens(tokens))
                .font(DS.bigNumber(20)).foregroundColor(DS.ink)
            if showsAPICost {
                Text(String(format: "\u{2248} $%.0f API", cost))
                    .dsCaption().monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.m)
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).dsCaption().lineLimit(1).minimumScaleFactor(0.85)
            Text(value).font(DS.bodyMedium).foregroundColor(DS.ink).monospacedDigit()
            if let sub {
                Text(sub).dsCaption().monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelBreakdownView: View {
    @Environment(\.showsAPICost) private var showsAPICost
    let models: [ModelUsage]
    var body: some View {
        let total = max(models.reduce(0) { $0 + $1.tokens.totalTokens }, 1)
        VStack(spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, m in
                if index > 0 { DSHairline() }
                HStack(spacing: DS.Spacing.s) {
                    Text(m.family)
                        .font(.system(size: 12, weight: .medium)).foregroundColor(DS.ink)
                        .frame(width: 72, alignment: .leading)
                        .lineLimit(1).help(m.model)
                    InkBar(fraction: Double(m.tokens.totalTokens) / Double(total))
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatTokens(m.tokens.totalTokens))
                            .font(.system(size: 11, weight: .medium)).foregroundColor(DS.ink).monospacedDigit()
                        if showsAPICost {
                            Text(String(format: "\u{2248} $%.2f", m.costUSD))
                                .dsCaption().monospacedDigit()
                        }
                    }
                    .frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

private struct ShowsAPICostKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var showsAPICost: Bool {
        get { self[ShowsAPICostKey.self] }
        set { self[ShowsAPICostKey.self] = newValue }
    }
}

/// Calendar ranges include today and exclude future or older activity.
func calendarDays(_ days: [DailyEntry], count: Int, now: Date = Date(), calendar: Calendar = .current) -> [DailyEntry] {
    guard count > 0,
          let start = calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: now)),
          let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return days.filter {
        guard let date = formatter.date(from: $0.date) else { return false }
        return date >= start && date < end
    }.sorted { $0.date > $1.date }
}
