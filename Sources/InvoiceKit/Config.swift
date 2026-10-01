import Foundation

/// Feste Angaben, die sich von Rechnung zu Rechnung nicht ändern.
/// Wird aus `Config/config.json` geladen.
public struct InvoiceConfig: Codable, Sendable, Equatable {
    public var currency: String
    /// Standard-Stundensatz. Weicht der Satz im PDF davon ab, gibt es eine Warnung.
    public var hourlyRate: Decimal
    /// Präfix für BT-22, z. B. "REF. " ergibt "REF. 26-1884".
    public var referenceNotePrefix: String
    /// BT-120: Begründung für durchlaufende Posten (USt-Kategorie E).
    public var disbursementExemptionReason: String
    public var seller: Seller
    public var buyer: Buyer
    public var payment: Payment

    public struct Seller: Codable, Sendable, Equatable {
        /// BT-29: Lieferantennummer beim Kunden.
        public var id: String
        public var name: String
        public var contactName: String
        public var phone: String
        public var email: String
        public var street: String
        public var postcode: String
        public var city: String
        public var country: String
        public var vatId: String
    }

    public struct Buyer: Codable, Sendable, Equatable {
        /// BT-46: Kennung des Käufers.
        public var id: String
        public var name: String
        /// Wird verwendet, wenn im PDF keine "Patentreferent"-Zeile steht.
        public var defaultContactName: String
        public var addressLine: String
        public var postcode: String
        public var city: String
        public var country: String
        /// BT-48: Umsatzsteuer-Identifikationsnummer des Käufers.
        public var vatId: String
    }

    public struct Payment: Codable, Sendable, Equatable {
        public var iban: String
        public var bic: String
        public var accountHolder: String
        public var terms: String
    }

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
        case currency, hourlyRate, referenceNotePrefix, disbursementExemptionReason, seller, buyer, payment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = try c.decode(String.self, forKey: .currency)
        let rate = try c.decode(String.self, forKey: .hourlyRate)
        guard let parsed = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: .hourlyRate, in: c, debugDescription: "Ungültiger Stundensatz: \(rate)")
        }
        hourlyRate = parsed
        referenceNotePrefix = try c.decode(String.self, forKey: .referenceNotePrefix)
        disbursementExemptionReason = try c.decode(String.self, forKey: .disbursementExemptionReason)
        seller = try c.decode(Seller.self, forKey: .seller)
        buyer = try c.decode(Buyer.self, forKey: .buyer)
        payment = try c.decode(Payment.self, forKey: .payment)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currency, forKey: .currency)
        try c.encode(hourlyRate.xmlAmount, forKey: .hourlyRate)
        try c.encode(referenceNotePrefix, forKey: .referenceNotePrefix)
        try c.encode(disbursementExemptionReason, forKey: .disbursementExemptionReason)
        try c.encode(seller, forKey: .seller)
        try c.encode(buyer, forKey: .buyer)
        try c.encode(payment, forKey: .payment)
    }
}
