//
//  Components.swift
//  GoldenArchive
//
//  Presentation layer — surfaces, buttons and small building blocks.
//  Gold glow is reserved for artwork and heroes, never behind small text.
//

import SwiftUI

// MARK: - Backgrounds & surfaces

struct ScreenBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            GAColor.cream
            LinearGradient(colors: [GAColor.creamDeep, GAColor.cream.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func gaBackground() -> some View {
        background(ScreenBackground())
    }

    func gaCard(padding: CGFloat = 16, radius: CGFloat = GATheme.cornerRadius) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(GAColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(GAColor.stroke, lineWidth: 1)
            )
            .shadow(color: GAColor.navy.opacity(0.07), radius: 10, x: 0, y: 5)
    }

    /// Thick glossy gold bezel used on navy hero panels.
    func goldBezel(radius: CGFloat = 26, width: CGFloat = 3) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(GAColor.goldRim, lineWidth: width)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius - width, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .padding(width)
        )
    }
}

/// Deep navy panel with a gold rim — the app's "display case".
struct NavyPanel<Content: View>: View {
    var radius: CGFloat = 26
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(GAColor.navyFill)
            )
            .goldBezel(radius: radius)
            .shadow(color: GAColor.navy.opacity(0.25), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Buttons

enum GAButtonKind {
    case primary
    case secondary
    case outline
    case destructive
    case quiet
}

struct GAButtonStyle: ButtonStyle {
    var kind: GAButtonKind = .primary
    var compact = false
    var fullWidth = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(compact ? .subheadline : .headline, design: .rounded).weight(.bold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundColor(foreground)
            .padding(.vertical, compact ? 9 : 14)
            .padding(.horizontal, compact ? 14 : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 38 : 50)
            .background(background(pressed: pressed))
            .overlay(border)
            .offset(y: pressed && kind == .primary ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return GAColor.text
        case .secondary: return GAColor.cream
        case .outline: return GAColor.navy
        case .destructive: return .white
        case .quiet: return GAColor.navy
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous)
        switch kind {
        case .primary:
            ZStack {
                shape.fill(GAColor.bronze).offset(y: pressed ? 1 : 3)
                shape.fill(GAColor.goldFill)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                    .padding(2)
            }
        case .secondary:
            shape.fill(GAColor.navyFill).opacity(pressed ? 0.85 : 1)
        case .outline:
            shape.fill(GAColor.card.opacity(pressed ? 0.7 : 1))
        case .destructive:
            shape.fill(GAColor.danger.opacity(pressed ? 0.85 : 1))
        case .quiet:
            shape.fill(GAColor.creamDeep.opacity(pressed ? 0.6 : 1))
        }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous)
        switch kind {
        case .primary: shape.strokeBorder(Color(hex: 0xB86E1E).opacity(0.55), lineWidth: 1)
        case .secondary: shape.strokeBorder(GAColor.gold.opacity(0.8), lineWidth: 1.5)
        case .outline: shape.strokeBorder(GAColor.navy.opacity(0.35), lineWidth: 1.5)
        case .destructive, .quiet: EmptyView()
        }
    }
}

extension ButtonStyle where Self == GAButtonStyle {
    static var gaPrimary: GAButtonStyle { GAButtonStyle(kind: .primary) }
    static var gaSecondary: GAButtonStyle { GAButtonStyle(kind: .secondary) }
    static var gaOutline: GAButtonStyle { GAButtonStyle(kind: .outline) }
    static var gaDestructive: GAButtonStyle { GAButtonStyle(kind: .destructive) }
    static var gaQuiet: GAButtonStyle { GAButtonStyle(kind: .quiet) }
    static func ga(_ kind: GAButtonKind, compact: Bool = false, fullWidth: Bool = true) -> GAButtonStyle {
        GAButtonStyle(kind: kind, compact: compact, fullWidth: fullWidth)
    }
}

/// Plain press feedback for tappable cards.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Small pieces

struct IconBadge: View {
    var symbol: String
    var tint: Color = GAColor.navy
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundColor(tint == GAColor.gold ? GAColor.navy : tint)
            .frame(width: size, height: size)
            .background(
                Circle().fill(tint == GAColor.gold ? GAColor.gold.opacity(0.9) : tint.opacity(0.12))
            )
            .accessibilityHidden(true)
    }
}

struct StatTile: View {
    static let minHeight: CGFloat = 128

    var value: String
    var label: String
    var symbol: String
    var tint: Color = GAColor.navy
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconBadge(symbol: symbol, tint: tint, size: 30)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(GAFont.number(.title2))
                .foregroundColor(GAColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(GAColor.textSecondary)
                .lineLimit(2)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: StatTile.minHeight, alignment: .topLeading)
        .gaCard(padding: 14, radius: 18)
        .accessibilityElement(children: .combine)
    }
}

struct GAProgressBar: View {
    var value: Double
    var height: CGFloat = 10
    var onNavy = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(onNavy ? Color.white.opacity(0.14) : GAColor.creamDeep)
                Capsule()
                    .fill(value >= 1 ? LinearGradient(colors: [GAColor.success, GAColor.success], startPoint: .leading, endPoint: .trailing) : GAColor.goldFill)
                    .frame(width: max(value > 0 ? height : 0, proxy.size.width * CGFloat(min(max(value, 0), 1))))
                Capsule().strokeBorder(onNavy ? GAColor.gold.opacity(0.5) : GAColor.stroke, lineWidth: 1)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GAFont.title(.title3))
                    .foregroundColor(GAColor.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(GAColor.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GAColor.bronzeText)
            }
        }
    }
}

struct StatusPill: View {
    var text: String
    var tint: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.bold)).lineLimit(1)
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.16)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }

    private var textColor: Color {
        switch tint {
        case GAColor.success: return GAColor.successText
        case GAColor.gold, GAColor.bronze: return GAColor.bronzeText
        case GAColor.ember: return GAColor.emberText
        case GAColor.silver: return GAColor.navy
        default: return tint
        }
    }
}

/// A quiet explanatory note, e.g. "This is not an appraisal".
struct InfoNote: View {
    var text: String
    var symbol: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(GAColor.navy)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundColor(GAColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GAColor.silver.opacity(0.45)))
    }
}

struct WarningNote: View {
    var text: String
    var symbol: String = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundColor(GAColor.emberText)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundColor(GAColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GAColor.ember.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(GAColor.ember.opacity(0.35), lineWidth: 1))
    }
}

struct KeyValueRow: View {
    var label: String
    var value: String
    var placeholder = "Not set"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(GAColor.textSecondary)
                .frame(minWidth: 96, alignment: .leading)
            Text(value.isBlank ? placeholder : value)
                .font(.subheadline.weight(value.isBlank ? .regular : .semibold))
                .foregroundColor(value.isBlank ? GAColor.textTertiary : GAColor.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// A navigation-looking row inside a card.
struct ActionRowLabel: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color = GAColor.navy
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(GAColor.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(GAColor.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundColor(GAColor.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundColor(GAColor.textTertiary)
        }
        .contentShape(Rectangle())
    }
}

struct EmptyStateView: View {
    var artwork: Artwork?
    var artSize = CGSize(width: 150, height: 120)
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            if let artwork {
                ArtworkView(artwork: artwork)
                    .frame(width: artSize.width, height: artSize.height)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(GAFont.title(.title3))
                .foregroundColor(GAColor.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundColor(GAColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.ga(.primary, fullWidth: false))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .gaCard()
    }
}

struct ToastView: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundColor(GAColor.gold)
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(GAColor.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(GAColor.navy))
        .overlay(Capsule().strokeBorder(GAColor.gold.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

struct ChoiceChip: View {
    var title: String
    var isSelected: Bool
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundColor(isSelected ? GAColor.cream : GAColor.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(isSelected ? GAColor.navy : GAColor.card))
            .overlay(Capsule().strokeBorder(isSelected ? GAColor.gold : GAColor.stroke, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TagChipsView: View {
    var tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(GAColor.navy)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(GAColor.silver.opacity(0.7)))
                }
            }
        }
    }
}

/// Segmented control styled for the app.
struct GASegmented<Value: Hashable & Identifiable>: View {
    var options: [Value]
    @Binding var selection: Value
    var title: (Value) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(selected ? GAColor.cream : GAColor.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? GAColor.navy : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(GAColor.creamDeep))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(GAColor.stroke, lineWidth: 1))
    }
}

extension View {
    /// Hides the default List background on every iOS version.
    @ViewBuilder
    func hideListBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    func toast(_ toast: Binding<Toast?>) -> some View {
        overlay(alignment: .bottom) {
            if let value = toast.wrappedValue {
                ToastView(toast: value)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                            withAnimation { if toast.wrappedValue?.id == value.id { toast.wrappedValue = nil } }
                        }
                    }
                    .onTapGesture { withAnimation { toast.wrappedValue = nil } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.wrappedValue)
    }
}
