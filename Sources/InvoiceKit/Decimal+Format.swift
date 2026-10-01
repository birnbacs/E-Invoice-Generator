import Foundation

extension Decimal {
    /// Kaufmännisch auf `scale` Nachkommastellen runden.
    public func rounded(_ scale: Int = 2) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }

    /// Betrag für das XML: Punkt als Dezimaltrenner, genau zwei Nachkommastellen.
    public var xmlAmount: String {
        Self.format(rounded(2), minFraction: 2, maxFraction: 2)
    }

    /// Menge für das XML: so viele Nachkommastellen wie nötig (max. 4).
    public var xmlQuantity: String {
        Self.format(self, minFraction: 0, maxFraction: 4)
    }

    /// Betrag zur Anzeige im deutschen Format, z. B. "2.025,00".
    public var germanAmount: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: self as NSDecimalNumber) ?? "\(self)"
    }

    /// Liest Beträge im deutschen Format: "2.025,00", "270", "7,5".
    public init?(german text: String) {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isNumber || $0 == "." }),
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        self = value
    }

    private static func format(_ value: Decimal, minFraction: Int, maxFraction: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = minFraction
        f.maximumFractionDigits = maxFraction
        f.minimumIntegerDigits = 1
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
