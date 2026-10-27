import SwiftUI

struct ContentView: View {
    @AppStorage("fractionPrecision") private var precision = 16
    @AppStorage("showsFeet") private var showsFeet = false
    /// The last finished sums, kept between launches.
    @AppStorage("history") private var savedHistory = Data()
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
                    rows: tapeRows,
                    showsClear: !converter.tape.isEmpty,
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
        .onAppear {
            if let history = try? JSONDecoder().decode([Calculation].self, from: savedHistory) {
                converter.restoreHistory(history)
            }
        }
        .onChange(of: converter.history) {
            savedHistory = (try? JSONEncoder().encode(converter.history)) ?? Data()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .sheet(isPresented: $showsTape) {
            TapeSheet(converter: converter, showsFeet: showsFeet) {
                converter.clearHistory()
            }
        }
    }

    private func fieldRow(_ field: Field, title: String, unit: String?) -> some View {
        FieldRow(
            title: title,
            note: converter.note(for: field),
            unit: unit,
            text: converter.text(for: field),
            isApproximate: converter.isApproximate(field),
            state: converter.state(of: field),
            cursor: converter.cursor,
            onTap: { converter.select(field) },
            onBeginCursor: {
                converter.edit(field)
                hapticTrigger += 1
            },
            onMoveCursor: { converter.moveCursor(to: $0) }
        )
    }

    /// The sum line's rows, oldest first: the finished sums, then the sum running now, or the
    /// hint when none is.
    private var tapeRows: [TapeRow] {
        var rows = converter.history.enumerated().map { index, calculation in
            TapeRow(id: "history-\(index)", expression: calculation.expression, total: calculation.total)
        }
        if converter.pendingSign != nil, let expression = converter.tapeExpression {
            rows.append(TapeRow(id: "running", expression: expression, total: nil))
        } else if !converter.sumFinished {
            rows.append(TapeRow(id: "hint", expression: nil, total: nil))
        }
        return rows
    }
}

/// One of the three values: its name small at the top, the figures as large as the width
/// allows. Tap to type a new number; hold to get a cursor, and slide to move it.
private struct FieldRow: View {
    let title: String
    /// Subtotal or total during a sum, and how the figures were rounded.
    let note: String?
    /// Nil when the figures carry their own marks (5' 3.25").
    let unit: String?
    let text: String
    let isApproximate: Bool
    let state: FieldState
    /// Where the caret is while editing, in characters.
    let cursor: Int
    let onTap: () -> Void
    let onBeginCursor: () -> Void
    let onMoveCursor: (Int) -> Void

    /// The figures' frame, to find the character under the finger.
    @State var textFrame = CGRect.zero
    @State var cursorGestureBegan = false

    private static let space = "field"
    private static let textPadding: CGFloat = 4

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
                Text(text)
                    .padding(.horizontal, Self.textPadding)
                    .background(
                        state == .selected ? Theme.accent.opacity(0.3) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: TextFrameKey.self, value: proxy.frame(in: .named(Self.space)))
                        }
                    }
                    .overlay(alignment: .leading) {
                        if state == .editing {
                            Caret()
                                .offset(x: Self.textPadding + CGFloat(cursor) * characterWidth - 1.5)
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
        .onPreferenceChange(TextFrameKey.self) { textFrame = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .gesture(cursorGesture.exclusively(before: TapGesture().onEnded { onTap() }))
        .coordinateSpace(.named(Self.space))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to type a new number, hold to edit this one")
        .accessibilityAction { onTap() }
        .accessibilityAction(named: "Edit") { onBeginCursor() }
    }

    /// The width of one character: the figures are in a fixed-width font.
    private var characterWidth: CGFloat {
        text.isEmpty ? 0 : max(textFrame.width - 2 * Self.textPadding, 0) / CGFloat(text.count)
    }

    /// The cursor position nearest to `x`, in the row's coordinates.
    private func cursorIndex(at x: CGFloat) -> Int {
        guard characterWidth > 0 else { return 0 }
        return Int(((x - textFrame.minX - Self.textPadding) / characterWidth).rounded())
    }

    /// Hold to edit in place, then slide the finger to move the cursor. The haptic tap comes
    /// when the cursor appears, as the finger is still down.
    private var cursorGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .onChanged { value in
                switch value {
                case .first:
                    cursorGestureBegan = false
                case .second(true, let drag):
                    if !cursorGestureBegan {
                        cursorGestureBegan = true
                        onBeginCursor()
                    }
                    if let drag {
                        onMoveCursor(cursorIndex(at: drag.location.x))
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                cursorGestureBegan = false
            }
    }
}

private struct TextFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Blinking insertion point in the figures of the field being edited.
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

/// One line of the sum line: a finished sum with its total, the sum running now, or the hint.
private struct TapeRow: Identifiable, Equatable {
    let id: String
    /// Nil for the hint.
    let expression: String?
    let total: String?
}

/// The sums on one line, always there so nothing moves when a sum starts. Swipe down for the
/// earlier ones (up to 10); a tap shows the whole tape.
private struct TapeLine: View {
    let rows: [TapeRow]
    let showsClear: Bool
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            rowView(row)
                                .frame(height: 40)
                                .id(row.id)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .defaultScrollAnchor(.bottom)
                .onChange(of: rows) {
                    if let last = rows.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            if showsClear {
                Button("Clear", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .themePanel()
    }

    @ViewBuilder
    private func rowView(_ row: TapeRow) -> some View {
        if let expression = row.expression {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(line(expression, total: row.total))
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
            .accessibilityLabel(String(line(expression, total: row.total).characters))
            .accessibilityHint("Shows the whole tape")
        } else {
            Text("Sum: type a length, then + or −")
                .font(.system(size: 13))
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// The sum, with " = total" in the accent once it has one.
    private func line(_ expression: String, total: String?) -> AttributedString {
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

/// The tape: the last finished sums, one length per line with each total, then the sum running
/// now. A standard sheet over the screen; it opens at the newest.
private struct TapeSheet: View {
    let converter: Converter
    let showsFeet: Bool
    let onClearAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tape")
                    .font(.headline)
                Spacer()
                // Rarely needed, so small and out of the way; Done is at the bottom.
                Button("Clear all") {
                    onClearAll()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(converter.history.enumerated()), id: \.offset) { index, calculation in
                        if index > 0 { separator }
                        entries(calculation.entries)
                        TotalBlock(
                            label: "Total",
                            rounding: calculation.fractionRounding,
                            isApproximate: calculation.fractionIsApproximate,
                            fraction: calculation.fraction,
                            unit: calculation.fractionUnit,
                            otherUnits: calculation.otherUnits
                        )
                    }
                    if converter.pendingSign != nil {
                        if !converter.history.isEmpty { separator }
                        entries(converter.tape)
                        TotalBlock(
                            label: "Subtotal",
                            rounding: converter.fractionRoundingNote,
                            isApproximate: converter.fractionRoundingNote != nil,
                            fraction: converter.valueText(for: .fraction),
                            unit: showsFeet ? "" : "in",
                            otherUnits: "\(converter.valueText(for: .inches))\(showsFeet ? "" : " in") · \(converter.valueText(for: .centimeters)) cm"
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .defaultScrollAnchor(.bottom)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accentDeep)
            .padding(16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.panel)
        .preferredColorScheme(.dark)
    }

    /// Between two sums.
    private var separator: some View {
        Theme.accent.opacity(0.35)
            .frame(height: 2)
            .padding(.vertical, 14)
    }

    private func entries(_ entries: [SumEntry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
            row(entry, first: index == 0)
            Theme.edge.frame(height: 1)
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
}

/// A sum's total: the fraction large, how it was rounded, and the other two units.
private struct TotalBlock: View {
    let label: String
    let rounding: String?
    let isApproximate: Bool
    let fraction: String
    /// "in", or empty when the fraction carries its own feet and inch marks.
    let unit: String
    let otherUnits: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let rounding {
                    Text(rounding)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isApproximate {
                    Text("≈").foregroundStyle(Theme.dim)
                }
                Text(fraction)
                    .foregroundStyle(Theme.accent)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
            }
            .font(.system(size: 34, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text(otherUnits)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// Native bordered buttons that fill the rest of the screen: digits, Delete (⌫), − and + in
/// the right-hand column, = the one prominent button.
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
                deleteKey
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
                    equalsKey
                }
            } else {
                GridRow {
                    separatorKey
                    digitKey(0)
                        .gridCellColumns(2)
                    equalsKey
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

    /// Tap deletes the character before the cursor; hold empties all three fields. On release
    /// after a hold the tap also arrives, and deletes nothing from the empty number.
    private var deleteKey: some View {
        Button {
            onKey(.delete)
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 28, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onClear() })
        .accessibilityLabel("Delete")
        .accessibilityHint("Hold to empty all three fields")
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

    /// Ends a sum with its total; otherwise ends typing. The other fields already follow every key.
    private var equalsKey: some View {
        Button {
            onKey(.equals)
        } label: {
            Text("=")
                .font(.system(size: 40, weight: .medium, design: .monospaced))
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accentDeep)
        .accessibilityLabel("Equals")
    }
}

#Preview {
    ContentView()
}
