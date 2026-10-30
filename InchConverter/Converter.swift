import Foundation

enum Field: String, CaseIterable, Codable {
    case inches, fraction, centimeters
}

enum FieldState {
    case inactive, selected, editing
}

enum SumSign: String, Codable {
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
    case half
}

/// An exact signed fraction in lowest terms, so that a sum of typed fractions stays exact.
struct Fraction: Equatable, Codable {
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

    /// `units` counts steps of 1/`denominator`: 29 units of 1/8 is 3 5/8. Not `reduced`, the
    /// denominator stays: 40 units of 1/16 is 2 8/16, not 2 1/2.
    init(units: Int, denominator: Int, reduced: Bool = true) {
        let remainder = units % denominator
        let divisor = reduced ? gcd(remainder, denominator) : 1
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
struct SumEntry: Equatable, Codable {
    let sign: SumSign
    let field: Field
    /// As typed (3 5/8, 2.5, 10), or what the field showed when nothing was typed.
    let text: String
    let inches: Double
    let exact: Fraction?
}

/// A finished sum, kept in the history as it was shown when = was pressed.
struct Calculation: Equatable, Codable {
    let entries: [SumEntry]
    /// The total as the sum line showed it, in the unit of the field = was pressed in.
    let total: String
    let fraction: String
    let fractionIsApproximate: Bool
    let fractionRounding: String?
    /// "in", or empty when the fraction carries its own feet and inch marks.
    let fractionUnit: String
    /// The total in decimal inches and centimeters, "7.31 in · 18.57 cm".
    let otherUnits: String

    var expression: String {
        Converter.expression(of: entries)
    }
}

/// The length (stored in inches), the numpad editing state of the three fields, and the sum.
///
/// Tapping a field selects it, so the next key replaces its whole value. Holding a field
/// edits it, so keys append to the current value. The other fields follow every key.
/// + and − add the field's value to a sum; = then shows the total in all three fields.
struct Converter {
    static let centimetersPerInch = 2.54
    static let maxDraftLength = 16
    static let historyLimit = 10

    /// Nil when the fields are empty (after holding Delete).
    private(set) var inches: Double? = 1
    private(set) var activeField: Field = .inches
    private(set) var isEditing = false
    private(set) var draft = ""
    /// Where the next key goes in the draft, in characters from the start.
    private(set) var cursor = 0
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
    /// The last finished sums, oldest first, at most `historyLimit`.
    private(set) var history: [Calculation] = []
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
            let (feet, rest) = splitIntoFeet(shownFraction.units, unitsPerInch: shownFraction.denominator)
            text = withFeet(feet, MixedFraction(units: rest, denominator: shownFraction.denominator, reduced: false).text)
            isZero = shownFraction.units == 0
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

    /// True when the field's figures are rounded: 2 decimals, or the fraction's precision.
    func isApproximate(_ field: Field) -> Bool {
        state(of: field) != .editing && rounding(for: field) != nil
    }

    var fractionIsApproximate: Bool {
        isApproximate(.fraction)
    }

    /// How far the field's figures are from the length, as "rounded 0.005" down" or
    /// "rounded 0.003 cm up"; nil when they are the length.
    func roundingNote(for field: Field) -> String? {
        guard let difference = rounding(for: field) else { return nil }
        let thousandths = Int((abs(difference) * 1000).rounded())
        let amount = thousandths == 0
            ? "< 0\(decimalSeparator)001"
            : "0\(decimalSeparator)\(String(format: "%03d", thousandths))"
        let unit = field == .centimeters ? " cm" : "\""
        return "rounded \(amount)\(unit) \(difference > 0 ? "up" : "down")"
    }

    var fractionRoundingNote: String? {
        roundingNote(for: .fraction)
    }

    /// The small words at the top right of a field: subtotal or total during a sum, and how the
    /// figures were rounded.
    func note(for field: Field) -> String? {
        guard state(of: field) != .editing else { return nil }
        var parts: [String] = []
        if pendingSign != nil {
            parts.append("subtotal")
        } else if sumFinished {
            parts.append("total")
        }
        if let rounding = roundingNote(for: field) {
            parts.append(rounding)
        } else if field == .fraction && sumFinished {
            parts.append("exact")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The sum so far, "3 5/8 + 2 7/16 +"; nil when no sum is running.
    var tapeExpression: String? {
        guard !tape.isEmpty else { return nil }
        let expression = Self.expression(of: tape)
        return pendingSign.map { "\(expression) \($0.symbol)" } ?? expression
    }

    /// "3 5/8 + 2 7/16 + 10 cm"
    static func expression(of entries: [SumEntry]) -> String {
        var parts: [String] = []
        for (index, entry) in entries.enumerated() {
            let text = entry.field == .centimeters ? "\(entry.text) cm" : entry.text
            parts.append(index == 0 && entry.sign == .plus ? text : "\(entry.sign.symbol) \(text)")
        }
        return parts.joined(separator: " ")
    }

    /// The total after =, in the active field's unit.
    var tapeTotal: String? {
        guard sumFinished else { return nil }
        let approximate = rounding(for: activeField) != nil ? "≈ " : ""
        let unit = activeField == .centimeters ? " cm" : ""
        return approximate + valueText(for: activeField) + unit
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

    /// The feet mark follows a whole number: 5, Feet, 3 gives 5' 3". With the cursor inside 53,
    /// after the 5, it gives 5' 3" too.
    var feetKeyEnabled: Bool {
        feetKeyShown && isEditing && !draft.contains("'")
            && !beforeCursor.isEmpty && beforeCursor.allSatisfy(\.isNumber)
    }

    // MARK: Actions

    mutating func select(_ field: Field) {
        // A length typed but not added to a running sum is dropped from its subtotal.
        if pendingSign != nil && hasTyped { applySum() }
        activeField = field
        isEditing = false
        draft = ""
        cursor = 0
        hasTyped = false
    }

    /// Starts editing the field's current value, the cursor at its end, instead of replacing it.
    /// On the field already being edited, the draft stays as it is.
    mutating func edit(_ field: Field) {
        guard !(field == activeField && isEditing) else { return }
        if pendingSign != nil && hasTyped { applySum() }
        activeField = field
        draft = editable(field)
        cursor = draft.count
        isEditing = true
        hasTyped = false
    }

    /// Moves the cursor, while editing; the next keys go there.
    mutating func moveCursor(to index: Int) {
        guard isEditing else { return }
        cursor = min(max(index, 0), draft.count)
        // Never between the feet mark and its space: "5'| 3" becomes "5' |3".
        if cursor > 0 && cursor < draft.count && beforeCursor.hasSuffix("'") { cursor += 1 }
    }

    /// Holding Delete: empties all three fields. During a sum they show the subtotal again.
    mutating func clear() {
        if sumFinished { clearSum() }
        isEditing = true
        draft = ""
        cursor = 0
        hasTyped = true
        updateFromDraft()
    }

    /// Ends the sum. The fields keep their values.
    mutating func clearSum() {
        tape = []
        pendingSign = nil
        sumFinished = false
    }

    /// Empties the history and ends the sum.
    mutating func clearHistory() {
        history = []
        clearSum()
    }

    /// The history saved by the last launch.
    mutating func restoreHistory(_ calculations: [Calculation]) {
        history = Array(calculations.suffix(Self.historyLimit))
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
        case .half: halve()
        }
    }

    // MARK: Formatting

    /// The fraction field's value in steps of 1/`denominator`, always in the selected
    /// denominator when it can be (2.5 at 1/64 is 2 32/64, not 2 1/2): the exact fraction as
    /// typed or summed (in its own denominator when finer, 3 5/64 at 1/16), or the length
    /// rounded to the precision. `value` carries the length's sign.
    private var shownFraction: (units: Int, denominator: Int, value: Double)? {
        guard let inches else { return nil }
        if fractionShowsExact, let exact {
            let denominator = precision % exact.denominator == 0 ? precision : exact.denominator
            return (abs(exact.numerator) * (denominator / exact.denominator), denominator, exact.value)
        }
        let units = Int((abs(inches) * Double(precision)).rounded())
        let magnitude = Double(units) / Double(precision)
        return (units, precision, inches < 0 ? -magnitude : magnitude)
    }

    /// How far the field's figures are from the length, in the field's unit (positive: rounded
    /// up); nil when they are the length.
    private func rounding(for field: Field) -> Double? {
        guard let inches else { return nil }
        let difference: Double
        switch field {
        case .inches:
            difference = shownDecimal(inches) - inches
        case .fraction:
            guard let shownFraction else { return nil }
            difference = shownFraction.value - inches
        case .centimeters:
            let centimeters = inches * Self.centimetersPerInch
            difference = shownDecimal(centimeters) - centimeters
        }
        return abs(difference) > 1e-9 ? difference : nil
    }

    /// A value as its two decimals show it.
    private func shownDecimal(_ value: Double) -> Double {
        let hundredths = (abs(value) * 100).rounded()
        return (value < 0 ? -hundredths : hundredths) / 100
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

    private var beforeCursor: Substring {
        draft.prefix(cursor)
    }

    /// The part of `text` after the feet mark, where the separator rules apply.
    private func inchesPart(_ text: Substring) -> Substring {
        guard let mark = text.firstIndex(of: "'") else { return text }
        return text[text.index(after: mark)...].drop { $0 == " " }
    }

    private var draftInches: Substring {
        inchesPart(Substring(draft))
    }

    /// What the separator key would add at the cursor, or nil if it can't be used there. The
    /// rules look at the inches typed before the cursor and at the whole number.
    private var separatorInsertion: String? {
        guard isEditing else { return activeField == .fraction ? nil : decimalSeparator }
        // Not among the feet: the cursor must be after "5' ".
        if let mark = draft.firstIndex(of: "'"), cursor <= draft.distance(from: draft.startIndex, to: mark) + 1 {
            return nil
        }
        let before = inchesPart(beforeCursor)
        guard activeField == .fraction else {
            return draftInches.contains(decimalSeparator) ? nil : decimalSeparator
        }
        // A space after the whole number, then one slash: inside 35/8, after the 3, a space
        // gives 3 5/8; nothing goes after the slash or right before it.
        let after = draftInches.dropFirst(before.count)
        if before.isEmpty || before.contains("/") { return nil }
        if before.contains(" ") { return draftInches.contains("/") ? nil : "/" }
        if draftInches.contains(" ") || after.hasPrefix("/") { return nil }
        return " "
    }

    private mutating func insert(_ text: String) {
        draft.insert(contentsOf: text, at: draft.index(draft.startIndex, offsetBy: cursor))
        cursor += text.count
    }

    private mutating func removeBeforeCursor(_ count: Int) {
        let end = draft.index(draft.startIndex, offsetBy: cursor)
        draft.removeSubrange(draft.index(end, offsetBy: -count)..<end)
        cursor -= count
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
            cursor = 0
        }
        hasTyped = true
    }

    private mutating func type(_ digit: String) {
        beginInput()
        guard draft.count < Self.maxDraftLength else { return }
        // A lone 0 typed last is replaced: 0 then 7 gives 7.
        if cursor == draft.count && draftInches == "0" { removeBeforeCursor(1) }
        insert(digit)
        updateFromDraft()
    }

    private mutating func typeSeparator() {
        guard let insertion = separatorInsertion else { return }
        beginInput()
        guard draft.count < Self.maxDraftLength else { return }
        // Only decimal fields get here with no inches before the cursor: "," becomes "0,".
        if inchesPart(beforeCursor).isEmpty { insert("0") }
        // "5", Space, Space gives "5/" for a fraction without a whole number.
        if insertion == "/" && beforeCursor.hasSuffix(" ") { removeBeforeCursor(1) }
        insert(insertion)
        updateFromDraft()
    }

    private mutating func typeFeet() {
        guard feetKeyEnabled, draft.count < Self.maxDraftLength else { return }
        beginInput()
        insert("' ")
        updateFromDraft()
    }

    private mutating func deleteBackward() {
        if sumFinished { clearSum() }
        if isEditing {
            if beforeCursor.hasSuffix("' ") {
                removeBeforeCursor(2)
            } else if cursor > 0 {
                removeBeforeCursor(1)
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

    // MARK: /2

    /// Halves the value shown. During a sum it halves the length being typed, which stays a
    /// draft to add with +, − or =; with nothing typed in a sum it does nothing. After a
    /// total, the half starts over, as a new number does.
    private mutating func halve() {
        if pendingSign != nil {
            guard hasNewInput, let length = parse(draft, in: activeField) else { return }
            draft = draftText(inches: length.inches / 2, exact: length.exact.map { Fraction($0.numerator, $0.denominator * 2) })
            cursor = draft.count
            updateFromDraft()
            return
        }
        if sumFinished { clearSum() }
        guard let inches else { return }
        setLength(inches / 2, exact: exact.map { Fraction($0.numerator, $0.denominator * 2) })
        // Keep the fraction exact even if it is finer than the precision: half of 3 5/64.
        select(activeField)
    }

    /// A length written as it would be typed in the active field: an exact fraction in full
    /// (1 13/16), decimals to four places at most (1.125).
    private func draftText(inches value: Double, exact: Fraction?) -> String {
        let sign = value < 0 ? "−" : ""
        let length = abs(value)
        switch activeField {
        case .fraction:
            let fraction = exact.map { MixedFraction(units: abs($0.numerator), denominator: $0.denominator) }
                ?? MixedFraction(rounding: length, toNearest: precision)
            guard showsFeet, fraction.units >= 12 * fraction.denominator else { return sign + fraction.text }
            let perFoot = 12 * fraction.denominator
            let rest = MixedFraction(units: fraction.units % perFoot, denominator: fraction.denominator)
            return "\(sign)\(fraction.units / perFoot)' \(rest.text)"
        case .inches:
            guard showsFeet, length >= 12 else { return sign + shortDecimal(length) }
            let feet = Int(length / 12)
            return "\(sign)\(feet)' \(shortDecimal(length - Double(feet * 12)))"
        case .centimeters:
            return sign + shortDecimal(length * Self.centimetersPerInch)
        }
    }

    /// Up to four decimals, without trailing zeros: 1.125, 2.5, 3.
    private func shortDecimal(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: decimalSeparator)
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
        history.append(Calculation(
            entries: tape,
            total: tapeTotal ?? "",
            fraction: valueText(for: .fraction),
            fractionIsApproximate: rounding(for: .fraction) != nil,
            fractionRounding: roundingNote(for: .fraction),
            fractionUnit: showsFeet ? "" : "in",
            otherUnits: "\(valueText(for: .inches))\(showsFeet ? "" : " in") · \(valueText(for: .centimeters)) cm"
        ))
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
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
        let rounded = rounding(for: activeField) != nil
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
