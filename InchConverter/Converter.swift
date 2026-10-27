import Foundation

enum Field: CaseIterable {
    case inches, fraction, centimeters
}

enum FieldState {
    case inactive, selected, editing
}

enum SumSign {
    case plus, minus

    var symbol: String {
        self == .plus ? "+" : "−"
    }
}

enum NumpadKey: Hashable {
    case digit(Int)
    case separator
    case feet
    case plus
    case minus
    case delete
    case equals
}

/// An exact signed fraction in lowest terms, so that a sum of typed fractions stays exact.
struct Fraction: Equatable {
    let numerator: Int
    let denominator: Int

    init(_ numerator: Int, _ denominator: Int) {
        let divisor = gcd(abs(numerator), denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    var value: Double {
        Double(numerator) / Double(denominator)
    }

    var negated: Fraction {
        Fraction(-numerator, denominator)
    }

    /// The sum, or nil when it no longer fits in an Int (the sum is then no longer exact).
    func adding(_ other: Fraction) -> Fraction? {
        let (left, overflow1) = numerator.multipliedReportingOverflow(by: other.denominator)
        let (right, overflow2) = other.numerator.multipliedReportingOverflow(by: denominator)
        let (sum, overflow3) = left.addingReportingOverflow(right)
        let (denominator, overflow4) = denominator.multipliedReportingOverflow(by: other.denominator)
        guard !(overflow1 || overflow2 || overflow3 || overflow4) else { return nil }
        return Fraction(sum, denominator)
    }
}

/// A non-negative mixed number such as 3 5/8, kept in lowest terms.
struct MixedFraction: Equatable {
    let whole: Int
    let numerator: Int
    let denominator: Int

    /// `units` counts steps of 1/`denominator`: 29 units of 1/8 is 3 5/8.
    init(units: Int, denominator: Int) {
        let remainder = units % denominator
        let divisor = gcd(remainder, denominator)
        whole = units / denominator
        numerator = remainder / divisor
        self.denominator = denominator / divisor
    }

    init(rounding value: Double, toNearest denominator: Int) {
        self.init(units: Int((value * Double(denominator)).rounded()), denominator: denominator)
    }

    /// Parses "3", "5/8" or "3 5/8". Returns nil for incomplete input such as "3 5/".
    init?(parsing text: String) {
        let halves = text.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count <= 2, let leading = Self.integers(in: halves[0]) else { return nil }
        if halves.count == 1 {
            guard leading.count == 1 else { return nil }
            self.init(units: leading[0], denominator: 1)
            return
        }
        guard let denominator = Int(halves[1]), denominator > 0 else { return nil }
        switch leading.count {
        case 1: self.init(units: leading[0], denominator: denominator)
        case 2: self.init(units: leading[0] * denominator + leading[1], denominator: denominator)
        default: return nil
        }
    }

    /// The whole value in steps of 1/`denominator`.
    var units: Int {
        whole * denominator + numerator
    }

    var value: Double {
        Double(whole) + Double(numerator) / Double(denominator)
    }

    var text: String {
        if numerator == 0 { return "\(whole)" }
        if whole == 0 { return "\(numerator)/\(denominator)" }
        return "\(whole) \(numerator)/\(denominator)"
    }

    /// The space-separated integers in `text`, or nil if any part isn't one.
    private static func integers(in text: Substring) -> [Int]? {
        let parts = text.split(separator: " ")
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : nil
    }
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    b == 0 ? a : gcd(b, a % b)
}

/// One length in a sum, in the field it was typed in.
struct SumEntry: Equatable {
    let sign: SumSign
    let field: Field
    /// As typed (3 5/8, 2.5, 10), or what the field showed when nothing was typed.
    let text: String
    let inches: Double
    let exact: Fraction?
}

/// The length (stored in inches), the numpad editing state of the three fields, and the sum.
///
/// Tapping a field selects it, so the next key replaces its whole value. Holding a field
/// edits it, so keys append to the current value. The other fields follow every key.
/// + and − add the field's value to a sum; = then shows the total in all three fields.
struct Converter {
    static let centimetersPerInch = 2.54
    static let maxDraftLength = 16

    /// Nil when the fields are empty (after holding Delete).
    private(set) var inches: Double? = 1
    private(set) var activeField: Field = .inches
    private(set) var isEditing = false
    private(set) var draft = ""
    /// True once a key changed the draft since the field was tapped or held.
    private var hasTyped = false
    /// Denominator the fraction field rounds to: 8, 16, 32 or 64.
    var precision = 16 {
        didSet { fractionShowsExact = false }
    }
    /// Shows the two inch fields as feet and inches (5' 3.25") instead of inches alone.
    var showsFeet = false
    /// The lengths added so far, in order.
    private(set) var tape: [SumEntry] = []
    /// The sign pressed last, waiting for the next length. Nil when no sum is running.
    private(set) var pendingSign: SumSign?
    /// True after = ended a sum: the fields show its total.
    private(set) var sumFinished = false
    /// The length as an exact fraction, when it is one: typed as a fraction, or a sum of those.
    private var exact: Fraction? = Fraction(1, 1)
    /// Shows `exact` as it is, even finer than the precision, until the precision changes.
    private var fractionShowsExact = false
    let decimalSeparator: String

    init(decimalSeparator: String = Locale.current.decimalSeparator ?? ".") {
        self.decimalSeparator = decimalSeparator
    }

    // MARK: What the screen shows

    func state(of field: Field) -> FieldState {
        guard field == activeField else { return .inactive }
        return isEditing ? .editing : .selected
    }

    /// The draft while the field is being edited, otherwise its value.
    func text(for field: Field) -> String {
        state(of: field) == .editing ? draft : valueText(for: field)
    }

    /// The field's value, whatever is being typed; empty when the fields are empty.
    func valueText(for field: Field) -> String {
        guard let inches, let shownFraction else { return "" }
        let length = abs(inches)
        let text: String
        let isZero: Bool
        switch field {
        case .inches:
            let hundredths = Int((length * 100).rounded())
            let (feet, rest) = splitIntoFeet(hundredths, unitsPerInch: 100)
            text = withFeet(feet, decimal(hundredths: rest))
            isZero = hundredths == 0
        case .fraction:
            let fraction = shownFraction.magnitude
            let (feet, rest) = splitIntoFeet(fraction.units, unitsPerInch: fraction.denominator)
            text = withFeet(feet, MixedFraction(units: rest, denominator: fraction.denominator).text)
            isZero = fraction.units == 0
        case .centimeters:
            let hundredths = Int((length * Self.centimetersPerInch * 100).rounded())
            text = decimal(hundredths: hundredths)
            isZero = hundredths == 0
        }
        return inches < 0 && !isZero ? "−" + text : text
    }

    /// Inches with two decimals, for a length other than the current one (a sum's entry).
    func decimalInchesText(_ value: Double) -> String {
        let hundredths = Int((abs(value) * 100).rounded())
        return (value < 0 && hundredths > 0 ? "−" : "") + decimal(hundredths: hundredths)
    }

    /// True when the fraction field shows a value rounded to the precision.
    var fractionIsApproximate: Bool {
        state(of: .fraction) != .editing && fractionRounding != nil
    }

    /// How far the fraction is from the length, as "rounded 0.005" down"; nil when it is the length.
    var fractionRoundingNote: String? {
        guard let difference = fractionRounding else { return nil }
        let thousandths = Int((abs(difference) * 1000).rounded())
        let amount = thousandths == 0
            ? "< 0\(decimalSeparator)001"
            : "0\(decimalSeparator)\(String(format: "%03d", thousandths))"
        return "rounded \(amount)\" \(difference > 0 ? "up" : "down")"
    }

    /// The small words at the top right of a field: subtotal or total during a sum, and how the
    /// fraction was rounded.
    func note(for field: Field) -> String? {
        guard state(of: field) != .editing else { return nil }
        var parts: [String] = []
        if pendingSign != nil {
            parts.append("subtotal")
        } else if sumFinished {
            parts.append("total")
        }
        if field == .fraction {
            if let rounding = fractionRoundingNote {
                parts.append(rounding)
            } else if sumFinished {
                parts.append("exact")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The sum so far, "3 5/8 + 2 7/16 +"; nil when no sum is running.
    var tapeExpression: String? {
        guard !tape.isEmpty else { return nil }
        var parts: [String] = []
        for (index, entry) in tape.enumerated() {
            let text = entry.field == .centimeters ? "\(entry.text) cm" : entry.text
            parts.append(index == 0 && entry.sign == .plus ? text : "\(entry.sign.symbol) \(text)")
        }
        if let pendingSign { parts.append(pendingSign.symbol) }
        return parts.joined(separator: " ")
    }

    /// The total after =, in the active field's unit.
    var tapeTotal: String? {
        guard sumFinished else { return nil }
        switch activeField {
        case .inches: return valueText(for: .inches)
        case .fraction: return (fractionRounding != nil ? "≈ " : "") + valueText(for: .fraction)
        case .centimeters: return valueText(for: .centimeters) + " cm"
        }
    }

    /// For the fraction field the separator key types the space after the whole number,
    /// then the fraction slash: 3, Space, 5, /, 8 gives "3 5/8".
    var separatorKeyLabel: String {
        guard activeField == .fraction else { return decimalSeparator }
        return separatorInsertion == "/" ? "/" : "Space"
    }

    var separatorKeyEnabled: Bool {
        separatorInsertion != nil
    }

    /// The Feet key is on the numpad for the inch fields while feet are shown.
    var feetKeyShown: Bool {
        showsFeet && activeField != .centimeters
    }

    /// The feet mark follows a whole number typed first: 5, Feet, 3 gives 5' 3".
    var feetKeyEnabled: Bool {
        feetKeyShown && isEditing && !draft.isEmpty && draft.allSatisfy(\.isNumber)
    }

    // MARK: Actions

    mutating func select(_ field: Field) {
        // A length typed but not added to a running sum is dropped from its subtotal.
        if pendingSign != nil && hasTyped { applySum() }
        activeField = field
        isEditing = false
        draft = ""
        hasTyped = false
    }

    /// Starts editing the field's current value instead of replacing it.
    mutating func edit(_ field: Field) {
        if pendingSign != nil && hasTyped { applySum() }
        activeField = field
        draft = editable(field)
        isEditing = true
        hasTyped = false
    }

    /// Holding Delete: empties all three fields. During a sum they show the subtotal again.
    mutating func clear() {
        if sumFinished { clearSum() }
        isEditing = true
        draft = ""
        hasTyped = true
        updateFromDraft()
    }

    /// Ends the sum. The fields keep their values.
    mutating func clearSum() {
        tape = []
        pendingSign = nil
        sumFinished = false
    }

    mutating func press(_ key: NumpadKey) {
        switch key {
        case .digit(let digit): type(String(digit))
        case .separator: typeSeparator()
        case .feet: typeFeet()
        case .plus: addToSum(.plus)
        case .minus: addToSum(.minus)
        case .delete: deleteBackward()
        case .equals: equals()
        }
    }

    // MARK: Formatting

    /// The fraction field's value: the exact fraction as typed or summed, or the length rounded
    /// to the precision. `value` carries the length's sign.
    private var shownFraction: (magnitude: MixedFraction, value: Double)? {
        guard let inches else { return nil }
        if fractionShowsExact, let exact {
            return (MixedFraction(units: abs(exact.numerator), denominator: exact.denominator), exact.value)
        }
        let magnitude = MixedFraction(rounding: abs(inches), toNearest: precision)
        return (magnitude, inches < 0 ? -magnitude.value : magnitude.value)
    }

    /// How far the fraction shown is from the length (positive: rounded up); nil when it is the length.
    private var fractionRounding: Double? {
        guard let inches, let shownFraction else { return nil }
        let difference = shownFraction.value - inches
        return abs(difference) > 1e-9 ? difference : nil
    }

    /// What holding a field starts editing from: its value without the closing inch mark.
    private func editable(_ field: Field) -> String {
        var text = valueText(for: field)
        if text.hasSuffix("\"") { text.removeLast() }
        return text
    }

    /// Splits a length counted in 1/`unitsPerInch` inch into whole feet and the rest, when feet
    /// are shown. Rounding comes first, so 11.999" shows as 1' 0.00", never 0' 12.00".
    private func splitIntoFeet(_ units: Int, unitsPerInch: Int) -> (feet: Int, rest: Int) {
        guard showsFeet else { return (0, units) }
        let perFoot = 12 * unitsPerInch
        return (units / perFoot, units % perFoot)
    }

    /// 5' 3.25" with feet shown, 3.25" under a foot, or the inches alone without feet.
    private func withFeet(_ feet: Int, _ inchesText: String) -> String {
        guard showsFeet else { return inchesText }
        return feet > 0 ? "\(feet)' \(inchesText)\"" : "\(inchesText)\""
    }

    /// Two decimals; rounded to hundredths beforehand, halves up (3.625 gives 3.63).
    private func decimal(hundredths: Int) -> String {
        "\(hundredths / 100)\(decimalSeparator)\(String(format: "%02d", hundredths % 100))"
    }

    // MARK: Reading what was typed

    private func parseDecimal(_ text: String) -> Double? {
        var text = text.replacingOccurrences(of: decimalSeparator, with: ".")
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasSuffix(".") { text += "0" }
        return Double(text)
    }

    /// Reads "5' 3.25" as 5 feet and "3.25"; "5'" as 5 feet and "0". Without a feet mark the
    /// whole text is inches.
    private func splitFeetMark(_ text: String) -> (feet: Int, inches: String)? {
        guard let mark = text.firstIndex(of: "'") else { return (0, text) }
        guard let feet = Int(text[..<mark]) else { return nil }
        let rest = text[text.index(after: mark)...].trimmingCharacters(in: .whitespaces)
        return (feet, rest.isEmpty ? "0" : rest)
    }

    /// The length a text in `field` stands for, and its exact fraction when typed as one. A
    /// leading − comes from holding a negative total.
    private func parse(_ text: String, in field: Field) -> (inches: Double, exact: Fraction?)? {
        var text = text
        let negative = text.hasPrefix("−")
        if negative { text.removeFirst() }
        let length: (inches: Double, exact: Fraction?)
        switch field {
        case .inches:
            guard let split = splitFeetMark(text), let value = parseDecimal(split.inches) else { return nil }
            length = (Double(split.feet * 12) + value, nil)
        case .centimeters:
            guard let value = parseDecimal(text) else { return nil }
            length = (value / Self.centimetersPerInch, nil)
        case .fraction:
            guard let split = splitFeetMark(text), let fraction = MixedFraction(parsing: split.inches) else { return nil }
            let exact = Fraction(split.feet * 12 * fraction.denominator + fraction.units, fraction.denominator)
            length = (exact.value, exact)
        }
        return negative ? (-length.inches, length.exact?.negated) : length
    }

    /// The part of the draft after the feet mark, where the separator rules apply.
    private var draftInches: Substring {
        guard let mark = draft.firstIndex(of: "'") else { return Substring(draft) }
        return draft[draft.index(after: mark)...].drop { $0 == " " }
    }

    /// What the separator key would add to the draft, or nil if it can't be used now.
    private var separatorInsertion: String? {
        let current = isEditing ? draftInches : ""
        guard activeField == .fraction else {
            return current.contains(decimalSeparator) ? nil : decimalSeparator
        }
        if current.isEmpty || current.contains("/") { return nil }
        return current.contains(" ") ? "/" : " "
    }

    /// True when something new was typed: not an empty draft, nor a held field left as it was.
    private var hasNewInput: Bool {
        isEditing && !draft.isEmpty && hasTyped
    }

    // MARK: Typing

    /// The first key of a new number: after a sum's total it starts over, and a selected value
    /// is replaced.
    private mutating func beginInput() {
        if sumFinished { clearSum() }
        if !isEditing {
            isEditing = true
            draft = ""
        }
        hasTyped = true
    }

    private mutating func type(_ digit: String) {
        beginInput()
        guard draft.count < Self.maxDraftLength else { return }
        if draftInches == "0" { draft.removeLast() }
        draft += digit
        updateFromDraft()
    }

    private mutating func typeSeparator() {
        guard let insertion = separatorInsertion else { return }
        beginInput()
        guard draft.count < Self.maxDraftLength else { return }
        // Only decimal fields get here with no inches typed: "," becomes "0,".
        if draftInches.isEmpty { draft += "0" }
        // "5", Space, Space gives "5/" for a fraction without a whole number.
        if insertion == "/" && draft.hasSuffix(" ") { draft.removeLast() }
        draft += insertion
        updateFromDraft()
    }

    private mutating func typeFeet() {
        guard feetKeyEnabled, draft.count < Self.maxDraftLength else { return }
        beginInput()
        draft += "' "
        updateFromDraft()
    }

    private mutating func deleteBackward() {
        if sumFinished { clearSum() }
        if isEditing {
            if draft.hasSuffix("' ") {
                draft.removeLast(2)
            } else if !draft.isEmpty {
                draft.removeLast()
            }
            hasTyped = true
            updateFromDraft()
        } else {
            // The whole value is selected, so delete removes all of it.
            clear()
        }
    }

    /// Shows what is being typed in the other two fields at once: the length itself, or during
    /// a sum the subtotal with it. An empty draft empties the fields (during a sum: the
    /// subtotal); one that can't be read, such as "3 5/", leaves them as they were. A fraction
    /// on its way, "7/1" before "7/16", shows as it reads (7"): the fields may jump.
    private mutating func updateFromDraft() {
        if draft.isEmpty {
            if pendingSign != nil { applySum() } else { setLength(nil, exact: nil) }
            return
        }
        if let pending = pendingSign {
            if let entry = typedEntry(sign: pending) { applySum(adding: entry) }
        } else if let length = parse(draft, in: activeField) {
            setLength(length.inches, exact: length.exact)
        }
    }

    private mutating func setLength(_ value: Double?, exact: Fraction?) {
        inches = exact?.value ?? value
        self.exact = exact
        fractionShowsExact = exact != nil
    }

    // MARK: = and the sum

    /// Ends the sum and shows its total; without a sum, ends typing (the value is already
    /// everywhere) and shows the field's value in full, 2.5 as 2.50.
    private mutating func equals() {
        guard let pending = pendingSign else {
            select(activeField)
            return
        }
        if hasNewInput {
            // Unreadable input such as "3 5/" stays, to be finished.
            guard let entry = typedEntry(sign: pending) else { return }
            tape.append(entry)
        }
        pendingSign = nil
        sumFinished = true
        applySum()
        select(activeField)
    }

    private mutating func addToSum(_ sign: SumSign) {
        if let pending = pendingSign {
            if hasNewInput {
                guard let entry = typedEntry(sign: pending) else { return }
                tape.append(entry)
            }
            // With nothing typed, a sign straight after another replaces it.
        } else {
            // A new sum starts with what the field holds: a typed length, or the value shown
            // (after =, the total, so the sum carries on from it).
            let entry = hasNewInput ? typedEntry(sign: .plus) : currentEntry
            guard let entry else { return }
            tape = [entry]
            sumFinished = false
        }
        pendingSign = sign
        applySum()
        hasTyped = false
        select(activeField)
    }

    /// The draft as a sum entry, or nil when it can't be read.
    private func typedEntry(sign: SumSign) -> SumEntry? {
        guard let length = parse(draft, in: activeField) else { return nil }
        var text = draft.trimmingCharacters(in: .whitespaces)
        if text.contains("'") && !text.hasSuffix("'") { text += "\"" }
        return SumEntry(sign: sign, field: activeField, text: text, inches: length.inches, exact: length.exact)
    }

    /// The value the active field shows, as the first entry of a sum; nil when it is empty.
    private var currentEntry: SumEntry? {
        guard let inches else { return nil }
        let rounded = activeField == .fraction && fractionRounding != nil
        return SumEntry(sign: .plus, field: activeField, text: (rounded ? "≈" : "") + valueText(for: activeField),
                        inches: inches, exact: exact)
    }

    /// Shows the sum of the tape, and of `extra` (the length being typed), in the fields; exact
    /// while every length is an exact fraction.
    private mutating func applySum(adding extra: SumEntry? = nil) {
        var total = 0.0
        var exactTotal: Fraction? = Fraction(0, 1)
        for entry in tape + (extra.map { [$0] } ?? []) {
            total += entry.sign == .plus ? entry.inches : -entry.inches
            let signed = entry.sign == .plus ? entry.exact : entry.exact?.negated
            if let sum = exactTotal, let signed {
                exactTotal = sum.adding(signed)
            } else {
                exactTotal = nil
            }
        }
        setLength(total, exact: exactTotal)
    }
}
