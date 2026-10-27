import Foundation

enum Field: CaseIterable {
    case inches, fraction, centimeters
}

enum FieldState {
    case inactive, selected, editing
}

enum NumpadKey: Hashable {
    case digit(Int)
    case separator
    case delete
    case enter
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

/// The length (stored in inches) and the numpad editing state of the three fields.
///
/// Tapping a field selects it, so the next key replaces its whole value. Holding a field
/// edits it, so keys append to the current value. Enter recalculates the other fields.
struct Converter {
    static let centimetersPerInch = 2.54
    static let maxDraftLength = 12

    private(set) var inches: Double = 1
    private(set) var activeField: Field = .inches
    private(set) var isEditing = false
    private(set) var draft = ""
    /// Denominator the fraction field rounds to: 8, 16, 32 or 64.
    var precision = 16 {
        didSet { enteredFraction = nil }
    }
    /// The fraction as the user typed it, shown instead of the rounded one until the value
    /// or the precision changes.
    private var enteredFraction: MixedFraction?
    let decimalSeparator: String

    init(decimalSeparator: String = Locale.current.decimalSeparator ?? ".") {
        self.decimalSeparator = decimalSeparator
    }

    func state(of field: Field) -> FieldState {
        guard field == activeField else { return .inactive }
        return isEditing ? .editing : .selected
    }

    /// The draft while the field is being edited, otherwise its formatted value.
    func text(for field: Field) -> String {
        state(of: field) == .editing ? draft : formatted(field)
    }

    /// True when the fraction field shows a value rounded to the precision.
    var fractionIsApproximate: Bool {
        state(of: .fraction) != .editing
            && enteredFraction == nil
            && abs(roundedFraction.value - inches) > 1e-9
    }

    /// For the fraction field the separator key types the space after the whole number,
    /// then the fraction slash: 3, ␣, 5, /, 8 gives "3 5/8".
    var separatorKeyLabel: String {
        guard activeField == .fraction else { return decimalSeparator }
        return separatorInsertion == "/" ? "/" : "␣"
    }

    var separatorKeyEnabled: Bool {
        separatorInsertion != nil
    }

    mutating func select(_ field: Field) {
        activeField = field
        isEditing = false
        draft = ""
    }

    /// Starts editing the field's current value instead of replacing it.
    mutating func edit(_ field: Field) {
        activeField = field
        draft = formatted(field)
        isEditing = true
    }

    mutating func clear() {
        isEditing = true
        draft = ""
    }

    mutating func press(_ key: NumpadKey) {
        switch key {
        case .digit(let digit): type(String(digit))
        case .separator: typeSeparator()
        case .delete: deleteBackward()
        case .enter: commit()
        }
    }

    private var roundedFraction: MixedFraction {
        MixedFraction(rounding: inches, toNearest: precision)
    }

    private func formatted(_ field: Field) -> String {
        switch field {
        case .inches: return decimal(inches)
        case .fraction: return (enteredFraction ?? roundedFraction).text
        case .centimeters: return decimal(inches * Self.centimetersPerInch)
        }
    }

    /// Two decimals, rounding halves up (3.625 → 3.63).
    private func decimal(_ value: Double) -> String {
        String(format: "%.2f", (value * 100).rounded() / 100)
            .replacingOccurrences(of: ".", with: decimalSeparator)
    }

    private func parseDecimal(_ text: String) -> Double? {
        var text = text.replacingOccurrences(of: decimalSeparator, with: ".")
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasSuffix(".") { text += "0" }
        return Double(text)
    }

    /// What the separator key would add to the draft, or nil if it can't be used now.
    private var separatorInsertion: String? {
        let current = isEditing ? draft : ""
        guard activeField == .fraction else {
            return current.contains(decimalSeparator) ? nil : decimalSeparator
        }
        if current.isEmpty || current.contains("/") { return nil }
        return current.contains(" ") ? "/" : " "
    }

    private mutating func startTypingIfSelected() {
        if !isEditing {
            isEditing = true
            draft = ""
        }
    }

    private mutating func type(_ digit: String) {
        startTypingIfSelected()
        guard draft.count < Self.maxDraftLength else { return }
        draft = draft == "0" ? digit : draft + digit
    }

    private mutating func typeSeparator() {
        guard let insertion = separatorInsertion else { return }
        startTypingIfSelected()
        guard draft.count < Self.maxDraftLength else { return }
        // Only decimal fields get here with an empty draft: "," becomes "0,".
        if draft.isEmpty { draft = "0" }
        // "5", ␣, ␣ gives "5/" for a fraction without a whole number.
        if insertion == "/" && draft.hasSuffix(" ") { draft.removeLast() }
        draft += insertion
    }

    private mutating func deleteBackward() {
        if isEditing {
            if !draft.isEmpty { draft.removeLast() }
        } else {
            // The whole value is selected, so delete removes all of it.
            clear()
        }
    }

    /// Recalculates the other fields from the active one. Invalid input reverts the field.
    private mutating func commit() {
        defer { select(activeField) }
        // An unchanged draft would replace the stored value with its rounded display.
        guard isEditing, draft != formatted(activeField) else { return }
        switch activeField {
        case .inches:
            if let value = parseDecimal(draft) {
                inches = value
                enteredFraction = nil
            }
        case .centimeters:
            if let value = parseDecimal(draft) {
                inches = value / Self.centimetersPerInch
                enteredFraction = nil
            }
        case .fraction:
            if let fraction = MixedFraction(parsing: draft) {
                inches = fraction.value
                enteredFraction = fraction
            }
        }
    }
}
