//
//  Theme.swift
//  GoldenArchive
//
//  Presentation layer — palette, type and UIKit appearance.
//

import SwiftUI
import UIKit
import CoreText

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum GAColor {
    // Brand palette
    static let gold = Color(hex: 0xF7C744)
    static let brightCoin = Color(hex: 0xFFE16A)
    static let bronze = Color(hex: 0xC87722)
    static let ember = Color(hex: 0xFF8B2C)
    static let navy = Color(hex: 0x172A46)
    static let cream = Color(hex: 0xFFF8E6)
    static let silver = Color(hex: 0xDDE4EC)
    static let success = Color(hex: 0x46B96B)
    static let text = Color(hex: 0x241A10)

    // Derived tones
    static let navyDeep = Color(hex: 0x0D1A2E)
    static let navySoft = Color(hex: 0x24406A)
    static let creamDeep = Color(hex: 0xF7ECCF)
    static let card = Color(hex: 0xFFFDF7)
    static let stroke = Color(hex: 0xEAD6A2)
    static let textSecondary = Color(hex: 0x6E5B45)
    static let textTertiary = Color(hex: 0x8F7C63)
    static let bronzeText = Color(hex: 0x8A4F12)
    static let successText = Color(hex: 0x2A7D45)
    static let danger = Color(hex: 0xB9402B)
    static let emberText = Color(hex: 0xA8520F)

    static let goldRim = LinearGradient(colors: [brightCoin, gold, bronze], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldFill = LinearGradient(colors: [brightCoin, gold, Color(hex: 0xE9A935)], startPoint: .top, endPoint: .bottom)
    static let navyFill = LinearGradient(colors: [navySoft, navy, navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum GAFont {
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Carter One", size: style == .largeTitle ? 34 : 28)
    }

    static func title(_ style: Font.TextStyle = .title2) -> Font {
        .custom("Carter One", size: style == .title2 ? 22 : 26)
    }

    static func headline() -> Font { .custom("Carter One", size: 17) }

    static func number(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .rounded).weight(.heavy).monospacedDigit()
    }

    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption
    static let footnote = Font.footnote
}

enum GATheme {
    static let cornerRadius: CGFloat = 20
    static let gutter: CGFloat = 16

    static func roundedUIFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func registerCarterOne() {
        guard let url = Bundle.main.url(forResource: "CarterOne", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func configureUIKitAppearance() {
        registerCarterOne()
        let ink = UIColor(hex: 0x241A10)
        let navy = UIColor(hex: 0x172A46)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(hex: 0xFFF8E6)
        nav.shadowColor = UIColor(hex: 0xEAD6A2)
        nav.titleTextAttributes = [.foregroundColor: ink, .font: roundedUIFont(size: 17, weight: .bold)]
        nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: roundedUIFont(size: 32, weight: .heavy)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = navy

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = navy
        tab.shadowColor = UIColor(hex: 0xC87722)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(hex: 0xDDE4EC, alpha: 0.72)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(hex: 0xDDE4EC, alpha: 0.72), .font: roundedUIFont(size: 10, weight: .semibold)]
        item.selected.iconColor = UIColor(hex: 0xF7C744)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(hex: 0xF7C744), .font: roundedUIFont(size: 10, weight: .bold)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) { UITabBar.appearance().scrollEdgeAppearance = tab }

        UISegmentedControl.appearance().selectedSegmentTintColor = navy
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(hex: 0xFFF8E6), .font: roundedUIFont(size: 13, weight: .bold)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: ink, .font: roundedUIFont(size: 13, weight: .semibold)], for: .normal)
        UISegmentedControl.appearance().backgroundColor = UIColor(hex: 0xF7ECCF)

        UITableView.appearance().backgroundColor = .clear
        UITextView.appearance().backgroundColor = .clear
    }
}

/// Formatting helpers for the UI.
enum GAFormat {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func money(_ amount: MoneyAmount) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = amount.currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount.amount as NSDecimalNumber) ?? "\(amount.amount) \(amount.currency)"
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }
}
