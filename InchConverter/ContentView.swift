import SwiftUI

struct ContentView: View {
    @AppStorage("fractionPrecision") private var precision = 16
    @State private var converter = Converter()
    @State private var hapticTrigger = 0

    var body: some View {
        VStack(spacing: 12) {
            fieldRow(.inches, title: "Inches", unit: "in")
            fieldRow(.fraction, title: "Fraction", unit: "in")
            fieldRow(.centimeters, title: "Centimeters", unit: "cm")

            VStack(alignment: .leading, spacing: 6) {
                Text("Fraction precision")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Fraction precision", selection: $precision) {
                    ForEach([8, 16, 32, 64], id: \.self) { denominator in
                        Text(verbatim: "1/\(denominator)").tag(denominator)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 4)

            Spacer(minLength: 12)

            Numpad(
                separatorLabel: converter.separatorKeyLabel,
                separatorEnabled: converter.separatorKeyEnabled,
                onKey: { converter.press($0) },
                onClear: {
                    converter.clear()
                    hapticTrigger += 1
                }
            )
            .frame(maxHeight: 400)
            .layoutPriority(1)
        }
        .padding()
        .onChange(of: precision, initial: true) {
            converter.precision = precision
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private func fieldRow(_ field: Field, title: String, unit: String) -> some View {
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

private struct FieldRow: View {
    let title: String
    let unit: String
    let text: String
    let isApproximate: Bool
    let state: FieldState
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 0)
            if isApproximate {
                Text("≈")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                Text(text)
                    .padding(.horizontal, 4)
                    .background(
                        state == .selected ? Color.accentColor.opacity(0.25) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                if state == .editing {
                    Caret()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            Text(unit)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, lineWidth: state == .inactive ? 0 : 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.4, perform: onLongPress)
    }
}

/// Blinking insertion point after the text of the field being edited.
private struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let isVisible = Int(context.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 30)
                .opacity(isVisible ? 1 : 0)
        }
    }
}

private struct Numpad: View {
    let separatorLabel: String
    let separatorEnabled: Bool
    let onKey: (NumpadKey) -> Void
    let onClear: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach([[7, 8, 9], [4, 5, 6], [1, 2, 3]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { digit in
                        Button(String(digit)) { onKey(.digit(digit)) }
                    }
                }
            }
            GridRow {
                Button(separatorLabel) { onKey(.separator) }
                    .disabled(!separatorEnabled)
                    .opacity(separatorEnabled ? 1 : 0.4)
                    .accessibilityLabel(separatorLabel == "␣" ? "Space" : separatorLabel)
                Button("0") { onKey(.digit(0)) }
                DeleteKey(onDelete: { onKey(.delete) }, onClear: onClear)
            }
            GridRow {
                Button("Enter") { onKey(.enter) }
                    .buttonStyle(KeyStyle(isProminent: true))
                    .gridCellColumns(3)
            }
        }
        .buttonStyle(KeyStyle())
    }
}

/// Tap deletes the last character, hold clears the whole number.
private struct DeleteKey: View {
    let onDelete: () -> Void
    let onClear: () -> Void
    @State private var isPressed = false

    var body: some View {
        Image(systemName: "delete.left")
            .keyAppearance(isPressed: isPressed)
            .onTapGesture(perform: onDelete)
            .onLongPressGesture(minimumDuration: 0.5, perform: onClear, onPressingChanged: { isPressed = $0 })
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
    }
}

private struct KeyStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .keyAppearance(isPressed: configuration.isPressed, isProminent: isProminent)
    }
}

private extension View {
    func keyAppearance(isPressed: Bool, isProminent: Bool = false) -> some View {
        self
            .font(.system(size: 28, weight: .medium, design: .rounded))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .background(
                isProminent ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .opacity(isPressed ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
}
