import SwiftUI

struct ContentView: View {
    @AppStorage("fractionPrecision") private var precision = 16
    @AppStorage("showsFeet") private var showsFeet = false
    @State private var converter = Converter()
    @State private var hapticTrigger = 0

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
    }

    private func fieldRow(_ field: Field, title: String, unit: String?) -> some View {
        FieldRow(
            title: title,
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
    /// Nil when the figures carry their own marks (5' 3.25").
    let unit: String?
    let text: String
    let isApproximate: Bool
    let state: FieldState
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state == .inactive ? Theme.dim : Theme.accent)
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

/// Native bordered buttons that fill the rest of the screen. Enter is the one prominent button.
private struct Numpad: View {
    let separatorLabel: String
    let separatorEnabled: Bool
    let feetShown: Bool
    let feetEnabled: Bool
    let onKey: (NumpadKey) -> Void
    let onClear: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach([[7, 8, 9], [4, 5, 6], [1, 2, 3]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { digit in
                        key(String(digit), isFigure: true) { onKey(.digit(digit)) }
                    }
                }
            }
            GridRow {
                key(separatorLabel, isFigure: separatorLabel != "Space") { onKey(.separator) }
                    .disabled(!separatorEnabled)
                key("0", isFigure: true) { onKey(.digit(0)) }
                // Tap deletes the last character; hold clears the number. On release after a
                // hold the tap also arrives, and deletes nothing from the empty number.
                key("Delete") { onKey(.delete) }
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onClear() })
                    .accessibilityHint("Hold to clear the number")
            }
            if feetShown {
                GridRow {
                    key("Feet") { onKey(.feet) }
                        .disabled(!feetEnabled)
                    enterKey
                        .gridCellColumns(2)
                }
            } else {
                GridRow {
                    enterKey
                        .gridCellColumns(3)
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
                .font(isFigure ? .system(size: 40, weight: .medium, design: .monospaced) : .system(size: 22, weight: .semibold))
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var enterKey: some View {
        Button {
            onKey(.enter)
        } label: {
            Text("Enter")
                .font(.system(size: 24, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accentDeep)
    }
}

#Preview {
    ContentView()
}
