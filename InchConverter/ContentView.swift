import SwiftUI

struct ContentView: View {
    @AppStorage("fractionPrecision") private var precision = 16
    @AppStorage("showsFeet") private var showsFeet = false
    @State private var converter = Converter()
    @State private var hapticTrigger = 0
    @State private var showsTape = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBand()
            VStack(spacing: 10) {
                fieldRow(.inches, title: showsFeet ? "Feet and inches" : "Inches", unit: showsFeet ? nil : "in")
                fieldRow(.fraction, title: showsFeet ? "Feet and inches, fraction" : "Inches, fraction", unit: showsFeet ? nil : "in")
                fieldRow(.centimeters, title: "Centimeters", unit: "cm")

                HStack(spacing: 10) {
                    Picker("Inch fields", selection: $showsFeet) {
                        Text("Inches").tag(false)
                        Text("Feet + in").tag(true)
                    }
                    Picker("Fraction precision", selection: $precision) {
                        ForEach([8, 16, 32, 64], id: \.self) { denominator in
                            Text(verbatim: "1/\(denominator)").tag(denominator)
                        }
                    }
                }
                .pickerStyle(.segmented)

                TapeLine(
                    expression: converter.tapeExpression,
                    total: converter.tapeTotal,
                    onOpen: { showsTape = true },
                    onClear: { converter.clearSum() }
                )

                Numpad(
                    separatorLabel: converter.separatorKeyLabel,
                    separatorEnabled: converter.separatorKeyEnabled,
                    feetShown: converter.feetKeyShown,
                    feetEnabled: converter.feetKeyEnabled,
                    onKey: { converter.press($0) },
                    onClear: {
                        converter.clear()
                        hapticTrigger += 1
                    }
                )
            }
            .padding(12)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accentDeep)
        .onChange(of: precision, initial: true) {
            converter.precision = precision
        }
        .onChange(of: showsFeet, initial: true) {
            converter.showsFeet = showsFeet
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .sheet(isPresented: $showsTape) {
            TapeSheet(converter: converter, showsFeet: showsFeet) {
                converter.clearSum()
            }
        }
    }

    private func fieldRow(_ field: Field, title: String, unit: String?) -> some View {
        FieldRow(
            title: title,
            note: converter.note(for: field),
            unit: unit,
            text: converter.text(for: field),
            isApproximate: field == .fraction && converter.fractionIsApproximate,
            state: converter.state(of: field),
            onTap: { converter.select(field) },
            onLongPress: {
                converter.edit(field)
                hapticTrigger += 1
            }
        )
    }
}

/// One of the three values: its name small at the top, the figures as large as the width allows.
private struct FieldRow: View {
    let title: String
    /// Subtotal or total during a sum, and how the fraction was rounded.
    let note: String?
    /// Nil when the figures carry their own marks (5' 3.25").
    let unit: String?
    let text: String
    let isApproximate: Bool
    let state: FieldState
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state == .inactive ? Theme.dim : Theme.accent)
                    .fixedSize()
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Spacer(minLength: 0)
                if isApproximate {
                    Text("≈")
                        .foregroundStyle(Theme.dim)
                }
                HStack(spacing: 2) {
                    Text(text)
                        .padding(.horizontal, 4)
                        .background(
                            state == .selected ? Theme.accent.opacity(0.3) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    if state == .editing {
                        Caret()
                    }
                }
                if let unit {
                    Text(unit)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
            }
            .font(.system(size: 48, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 88)
        .themePanel(active: state != .inactive)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.4, perform: onLongPress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to type a new number, hold to edit this one")
    }
}

/// Blinking insertion point after the figures of the field being edited.
private struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let isVisible = Int(context.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 3, height: 40)
                .opacity(isVisible ? 1 : 0)
        }
    }
}

/// The sum on one line, always there so nothing moves when a sum starts. The end stays in
/// sight; a tap shows the whole sum.
private struct TapeLine: View {
    let expression: String?
    let total: String?
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let expression {
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Text(line(expression))
                            .font(.system(size: 15, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .accessibilityHidden(true)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(line(expression).characters))
                .accessibilityHint("Shows the whole sum")
                Button("Clear", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Text("Sum: type a length, then + or −")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .themePanel()
    }

    /// The sum, with " = total" in the accent after Enter.
    private func line(_ expression: String) -> AttributedString {
        var text = AttributedString(expression)
        if let total {
            text.append(AttributedString(" = "))
            var totalText = AttributedString(total)
            totalText.foregroundColor = Theme.accent
            text.append(totalText)
        }
        return text
    }
}

/// The whole sum, one length per line, and the total. A standard sheet over the screen.
private struct TapeSheet: View {
    let converter: Converter
    let showsFeet: Bool
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sum")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .tint(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(converter.tape.enumerated()), id: \.offset) { index, entry in
                        row(entry, first: index == 0)
                        Theme.edge.frame(height: 1)
                    }
                    total
                }
                .padding(.horizontal, 16)
            }

            Button {
                onClear()
                dismiss()
            } label: {
                Text("Clear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)
            .padding(16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.panel)
        .preferredColorScheme(.dark)
        .onChange(of: converter.tape.isEmpty) {
            if converter.tape.isEmpty { dismiss() }
        }
    }

    private func row(_ entry: SumEntry, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(first && entry.sign == .plus ? " " : entry.sign.symbol)
                .font(.system(size: 22, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, alignment: .leading)
            if entry.field == .centimeters {
                Text("\(converter.decimalInchesText(entry.inches)) in")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 8)
            Text(entry.text)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit(of: entry))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .frame(width: 26, alignment: .leading)
        }
        .frame(height: 44)
    }

    /// cm, in, or nothing when the entry carries its own feet and inch marks.
    private func unit(of entry: SumEntry) -> String {
        if entry.field == .centimeters { return "cm" }
        return entry.text.hasSuffix("\"") || entry.text.hasSuffix("'") ? "" : "in"
    }

    private var total: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(converter.sumFinished ? "Total" : "Subtotal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let rounding = converter.fractionRoundingNote {
                    Text(rounding)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if converter.fractionRoundingNote != nil {
                    Text("≈").foregroundStyle(Theme.dim)
                }
                Text(converter.valueText(for: .fraction))
                    .foregroundStyle(Theme.accent)
                if !showsFeet {
                    Text("in")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
            }
            .font(.system(size: 34, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text("\(converter.valueText(for: .inches))\(showsFeet ? "" : " in") · \(converter.valueText(for: .centimeters)) cm")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// Native bordered buttons that fill the rest of the screen: digits, Delete, − and + in the
/// right-hand column, Enter the one prominent button.
private struct Numpad: View {
    let separatorLabel: String
    let separatorEnabled: Bool
    let feetShown: Bool
    let feetEnabled: Bool
    let onKey: (NumpadKey) -> Void
    let onClear: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                digitKey(7)
                digitKey(8)
                digitKey(9)
                // Tap deletes the last character; hold clears the number. On release after a
                // hold the tap also arrives, and deletes nothing from the empty number.
                key("Delete") { onKey(.delete) }
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onClear() })
                    .accessibilityHint("Hold to clear the number")
            }
            GridRow {
                digitKey(4)
                digitKey(5)
                digitKey(6)
                signKey(.minus, label: "Minus")
            }
            GridRow {
                digitKey(1)
                digitKey(2)
                digitKey(3)
                signKey(.plus, label: "Plus")
            }
            if feetShown {
                GridRow {
                    separatorKey
                    digitKey(0)
                    key("Feet") { onKey(.feet) }
                        .disabled(!feetEnabled)
                    enterKey
                }
            } else {
                GridRow {
                    separatorKey
                    digitKey(0)
                        .gridCellColumns(2)
                    enterKey
                }
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(.white)
    }

    private func key(_ title: String, isFigure: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(isFigure ? .system(size: 40, weight: .medium, design: .monospaced) : .system(size: 20, weight: .semibold))
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func digitKey(_ digit: Int) -> some View {
        key(String(digit), isFigure: true) { onKey(.digit(digit)) }
    }

    private func signKey(_ sign: SumSign, label: String) -> some View {
        key(sign.symbol, isFigure: true) { onKey(sign == .plus ? .plus : .minus) }
            .tint(Theme.accent)
            .accessibilityLabel(label)
    }

    private var separatorKey: some View {
        key(separatorLabel, isFigure: separatorLabel != "Space") { onKey(.separator) }
            .disabled(!separatorEnabled)
            .accessibilityLabel(separatorLabel)
    }

    private var enterKey: some View {
        Button {
            onKey(.enter)
        } label: {
            Text("Enter")
                .font(.system(size: 22, weight: .semibold))
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accentDeep)
    }
}

#Preview {
    ContentView()
}
