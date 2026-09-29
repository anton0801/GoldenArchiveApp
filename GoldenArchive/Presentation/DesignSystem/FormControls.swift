//
//  FormControls.swift
//  GoldenArchive
//
//  Presentation layer — labelled inputs used by every editor.
//

import SwiftUI

struct FormCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(0.8)
                    .foregroundColor(GAColor.bronzeText)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gaCard()
    }
}

struct FieldLabel: View {
    var title: String
    var required = false

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(GAColor.text)
            if required {
                Text("*")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GAColor.danger)
                    .accessibilityLabel("required")
            }
        }
    }
}

struct FieldErrorText: View {
    var message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(GAColor.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InputChrome: ViewModifier {
    var hasError: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hasError ? GAColor.danger : GAColor.stroke, lineWidth: hasError ? 1.5 : 1)
            )
    }
}

extension View {
    func inputChrome(hasError: Bool = false) -> some View {
        modifier(InputChrome(hasError: hasError))
    }
}

struct GATextField: View {
    var title: String
    @Binding var text: String
    var prompt: String = ""
    var required = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var unit: String?
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: title, required: required)
            HStack(spacing: 8) {
                TextField(prompt, text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .disableAutocorrection(keyboard != .default)
                    .foregroundColor(GAColor.text)
                    .accessibilityLabel(title)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(GAColor.textSecondary)
                }
            }
            .inputChrome(hasError: error != nil)
            FieldErrorText(message: error)
        }
    }
}

struct GATextArea: View {
    var title: String
    @Binding var text: String
    var prompt: String = ""
    var minHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: title)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .foregroundColor(GAColor.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
                    .foregroundColor(GAColor.text)
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(GAColor.stroke, lineWidth: 1))
        }
    }
}

struct GAToggleRow: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(GAColor.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(GAColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(GAColor.success)
    }
}

/// A picker rendered as a menu inside the input chrome.
struct GAMenuPicker<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [(Value, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: title)
            Menu {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        selection = option.0
                    } label: {
                        if option.0 == selection {
                            Label(option.1, systemImage: "checkmark")
                        } else {
                            Text(option.1)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(options.first { $0.0 == selection }?.1 ?? "Choose")
                        .foregroundColor(GAColor.text)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(GAColor.textSecondary)
                }
                .inputChrome()
            }
            .accessibilityLabel(title)
            .accessibilityValue(options.first { $0.0 == selection }?.1 ?? "")
        }
    }
}

struct QuantityStepper: View {
    var title: String = "Quantity"
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...9999
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FieldLabel(title: title)
                Spacer()
                HStack(spacing: 0) {
                    stepButton("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - 1) }
                    Text("\(value)")
                        .font(GAFont.number(.headline))
                        .foregroundColor(GAColor.text)
                        .frame(minWidth: 48)
                    stepButton("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + 1) }
                }
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().strokeBorder(GAColor.stroke, lineWidth: 1))
            }
            FieldErrorText(message: error)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundColor(enabled ? GAColor.navy : GAColor.textTertiary)
                .frame(width: 44, height: 38)
        }
        .disabled(!enabled)
    }
}

struct TagEditor: View {
    @Binding var tags: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "Tags")
            HStack(spacing: 8) {
                TextField("Add a tag", text: $draft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .inputChrome()
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.ga(.quiet, compact: true, fullWidth: false))
                .disabled(draft.isBlank)
                .accessibilityLabel("Add tag")
            }
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("#\(tag)").font(.caption.weight(.semibold))
                                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                                }
                                .foregroundColor(GAColor.navy)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(GAColor.silver.opacity(0.8)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                    }
                }
            }
        }
    }

    private func add() {
        let tag = draft.trimmed.replacingOccurrences(of: "#", with: "")
        guard !tag.isEmpty else { return }
        tags = (tags + [tag]).cleanedTags()
        draft = ""
    }
}

struct GADateRow: View {
    var title: String
    @Binding var date: Date
    var range: PartialRangeThrough<Date> = ...Date().addingTimeInterval(86_400)

    var body: some View {
        DatePicker(selection: $date, in: range, displayedComponents: .date) {
            FieldLabel(title: title)
        }
        .tint(GAColor.navy)
    }
}

/// Optional date: a toggle reveals the picker.
struct GAOptionalDateRow: View {
    var title: String
    @Binding var date: Date?
    var allowFuture = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? (date ?? Date()) : nil }
            )) {
                FieldLabel(title: title)
            }
            .tint(GAColor.success)
            if let current = date {
                DatePicker(
                    "",
                    selection: Binding(get: { current }, set: { date = $0 }),
                    in: allowFuture ? Date.distantPast...Date.distantFuture : Date.distantPast...Date().addingTimeInterval(86_400),
                    displayedComponents: .date
                )
                .labelsHidden()
                .tint(GAColor.navy)
            }
        }
    }
}

extension Array where Element == FieldError {
    func message(for field: CoinField) -> String? {
        first { $0.field == field }?.message
    }
}
