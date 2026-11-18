import SwiftUI
import AppKit

/// Single source of truth for Quota's visual language. Same values as FocusGuard 1.2
/// (the Displace website palette). System fonts only: Suisse Intl is licensed and never bundled.
enum DS {
    // MARK: Color tokens

    static let ink = Color(hex: 0x1C1C1C)
    static let inkSecondary = Color(hex: 0x686C6D)
    static let inkTertiary = Color(hex: 0xA5A7A8)
    static let surface = Color.white
    static let canvas = Color(hex: 0xF5F5F5)
    static let border = Color(hex: 0xDBDBDB)
    static let hairline = Color(hex: 0xEDEDED)
    static let accent = Color(hex: 0xFF5831)
    static let accentFill = Color(hex: 0xFFE7B6)
    static let danger = Color(hex: 0xA92924)

    // MARK: Type tokens

    /// 12pt semibold uppercase title label.
    static let titleFont = Font.system(size: 12, weight: .semibold)
    static let titleTracking: CGFloat = 0.6
    /// 10pt monospaced uppercase eyebrow.
    static let eyebrowFont = Font.system(size: 10, design: .monospaced)
    static let eyebrowTracking: CGFloat = 0.8
    static let bodyFont = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let captionFont = Font.system(size: 11)
    static func bigNumber(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .light).monospacedDigit()
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 4
        static let card: CGFloat = 4
        static let pill: CGFloat = 999
    }

    enum Layout {
        static let popover = CGSize(width: 420, height: 520)
    }

    enum Motion {
        static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        static var quick: Animation? { reduce ? nil : .easeInOut(duration: 0.15) }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Text and container modifiers

extension View {
    /// 12pt semibold uppercase title label.
    func dsTitle() -> some View {
        font(DS.titleFont).tracking(DS.titleTracking).textCase(.uppercase).foregroundColor(DS.ink)
    }
    /// 10pt monospaced uppercase grey eyebrow.
    func dsEyebrow() -> some View {
        font(DS.eyebrowFont).tracking(DS.eyebrowTracking).textCase(.uppercase).foregroundColor(DS.inkSecondary)
    }
    func dsCaption() -> some View {
        font(DS.captionFont).foregroundColor(DS.inkSecondary)
    }
    /// White card with a 1px border.
    func dsCard() -> some View {
        background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.border, lineWidth: 1))
    }
}

/// 1px hairline row separator.
struct DSHairline: View {
    var body: some View { Rectangle().fill(DS.hairline).frame(height: 1) }
}

// MARK: - Button styles

struct DSPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(enabled ? .white : DS.inkTertiary)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(enabled ? DS.ink : DS.canvas, in: RoundedRectangle(cornerRadius: DS.Radius.control))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    var fullWidth = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height < 32 ? 12 : 13, weight: .medium))
            .foregroundColor(enabled ? DS.ink : DS.inkTertiary)
            .padding(.horizontal, height < 32 ? 10 : 0)
            .frame(maxWidth: fullWidth ? .infinity : nil).frame(height: height)
            .background(enabled ? DS.surface : DS.canvas, in: RoundedRectangle(cornerRadius: DS.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).stroke(enabled ? DS.border : DS.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}
extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
    static var dsSecondarySmall: DSSecondaryButtonStyle { DSSecondaryButtonStyle(height: 26, fullWidth: false) }
}

// MARK: - Segmented control

/// Boxed segmented control: 1px border, selected segment ink fill with white text.
struct DSSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let on = opt.0 == selection
                Button { withAnimation(DS.Motion.quick) { selection = opt.0 } } label: {
                    Text(opt.1).font(.system(size: 12, weight: .medium))
                        .foregroundColor(on ? .white : DS.ink)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(on ? DS.ink : DS.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).stroke(DS.border, lineWidth: 1))
    }
}

// MARK: - Status pill

/// Status is never color alone: every pill carries a word.
struct DSPill: View {
    enum Style { case low, reached, outline }
    let style: Style
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            if style == .low { Circle().fill(DS.accent).frame(width: 6, height: 6) }
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(DS.titleTracking)
        }
        .foregroundColor(style == .reached ? .white : DS.ink)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(fill))
        .overlay(Capsule().stroke(style == .outline ? DS.ink : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var fill: Color {
        switch style {
        case .low: return DS.accentFill
        case .reached: return DS.danger
        case .outline: return DS.surface
        }
    }
}

// MARK: - Progress bar

/// Thin bar: hairline track, ink fill; accent under 20% left, danger at 0.
struct DSProgressBar: View {
    /// Percent left, 0...100.
    let remaining: Double
    var muted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(DS.hairline)
                RoundedRectangle(cornerRadius: 2).fill(fill)
                    .frame(width: max(reached ? 4 : 0, geo.size.width * remaining / 100))
            }
        }
        .frame(height: 4)
    }

    private var reached: Bool { remaining < 0.5 }
    private var fill: Color {
        if muted { return DS.inkTertiary }
        if reached { return DS.danger }
        return remaining < 20 ? DS.accent : DS.ink
    }
}

// MARK: - Notice

/// Surface row with a 2pt accent rule on the left, ink title and caption body.
struct DSNotice: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(DS.ink)
            if let message {
                Text(message).font(DS.captionFont).foregroundColor(DS.inkSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.border, lineWidth: 1))
        .overlay(alignment: .leading) { Rectangle().fill(DS.accent).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }
}
