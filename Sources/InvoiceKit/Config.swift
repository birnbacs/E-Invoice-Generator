import Foundation

/// Globale Einstellungen und feste Textbausteine aus `Config/config.json`.
public struct InvoiceConfig: Codable, Sendable, Equatable {
    public var currency: String
    /// Käuferkennung für BT-46.
    public var buyerID: String
    /// Standard-Stundensatz. Weicht der Satz im PDF davon ab, gibt es eine Warnung.
    public var hourlyRate: Decimal
    /// Präfix für BT-22, z. B. "REF. " ergibt "REF. 26-1884".
    public var referenceNotePrefix: String
    /// BT-120: Begründung für durchlaufende Posten (USt-Kategorie E).
    public var disbursementExemptionReason: String

    public static func load(from url: URL) throws -> InvoiceConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(InvoiceConfig.self, from: data)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension InvoiceConfig {
    // Decimal als String in der JSON-Datei, damit "270.00" nicht zu 269.99999 wird.
    enum CodingKeys: String, CodingKey {
        case currency, buyerID, hourlyRate, referenceNotePrefix, disbursementExemptionReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = try c.decode(String.self, forKey: .currency)
        buyerID = try c.decodeIfPresent(String.self, forKey: .buyerID) ?? "A1"
        let rate = try c.decode(String.self, forKey: .hourlyRate)
        guard let parsed = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: .hourlyRate, in: c, debugDescription: "Ungültiger Stundensatz: \(rate)")
        }
        hourlyRate = parsed
        referenceNotePrefix = try c.decode(String.self, forKey: .referenceNotePrefix)
        disbursementExemptionReason = try c.decode(String.self, forKey: .disbursementExemptionReason)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currency, forKey: .currency)
        try c.encode(buyerID, forKey: .buyerID)
        try c.encode(hourlyRate.xmlAmount, forKey: .hourlyRate)
        try c.encode(referenceNotePrefix, forKey: .referenceNotePrefix)
        try c.encode(disbursementExemptionReason, forKey: .disbursementExemptionReason)
    }
}
