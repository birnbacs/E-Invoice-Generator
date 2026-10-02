import Foundation

/// Die variablen Daten einer Rechnung, wie sie aus dem PDF gelesen werden.
public struct Invoice: Sendable, Equatable {
    public var number: String
    public var issueDate: Date
    /// Zahlungsfrist in Tagen, aus dem Zahlungshinweis des PDF gelesen.
    public var paymentTermDays: Int
    /// "Ihr Zeichen" – wird als "REF. <Aktenzeichen>" in BT-22 geschrieben.
    public var fileReference: String
    /// "Unser Zeichen"
    public var ourReference: String?
    public var billingPeriod: DateInterval
    /// "Patentreferent ..." aus dem PDF, sonst nil.
    public var buyerContactName: String?
    public var seller: Seller?
    public var buyer: Buyer?
    public var payment: Payment?
    public var lines: [InvoiceLine]
    public var vatRate: Decimal

    /// Summen, wie sie im PDF stehen. Dienen nur zur Kontrolle.
    public var statedNetTotal: Decimal
    public var statedVatAmount: Decimal
    public var statedGrandTotal: Decimal

    public var taxableLines: [InvoiceLine] { lines.filter { $0.kind == .service } }
    public var disbursementLines: [InvoiceLine] { lines.filter { $0.kind == .disbursement } }

    public var taxableTotal: Decimal { taxableLines.reduce(0) { $0 + $1.amount } }
    public var disbursementTotal: Decimal { disbursementLines.reduce(0) { $0 + $1.amount } }
    public var lineTotal: Decimal { taxableTotal + disbursementTotal }
    public var vatAmount: Decimal { (taxableTotal * vatRate / 100).rounded(2) }
    public var grandTotal: Decimal { lineTotal + vatAmount }

    public struct Seller: Sendable, Equatable {
        public var id: String?
        public var name: String
        public var contactName: String?
        public var phone: String?
        public var email: String?
        public var street: String
        public var postcode: String
        public var city: String
        public var country: String
        public var vatId: String?
    }

    public struct Buyer: Sendable, Equatable {
        public var id: String?
        public var name: String
        public var addressLines: [String]
        public var postcode: String
        public var city: String
        public var country: String
        public var vatId: String?
    }

    public struct Payment: Sendable, Equatable {
        public var iban: String
        public var bic: String
        public var accountHolder: String?
        public var terms: String
    }

    /// Prüft, ob die im PDF angegebenen Summen mit den Positionen übereinstimmen.
    /// Wirft einen Fehler, wenn nicht – dann darf keine E-Rechnung erzeugt werden.
    public func validate() throws {
        var problems: [String] = []
        if lines.isEmpty { problems.append("Keine Rechnungspositionen gefunden.") }
        if taxableLines.isEmpty { problems.append("Keine umsatzsteuerpflichtige Position gefunden.") }
        for line in lines where line.quantity * line.unitPrice != line.amount {
            problems.append("Position \(line.id): \(line.quantity.xmlQuantity) × \(line.unitPrice.germanAmount) ergibt nicht \(line.amount.germanAmount).")
        }
        if taxableTotal != statedNetTotal {
            problems.append("Zwischensumme laut PDF \(statedNetTotal.germanAmount), Summe der Positionen \(taxableTotal.germanAmount).")
        }
        if vatAmount != statedVatAmount {
            problems.append("Umsatzsteuer laut PDF \(statedVatAmount.germanAmount), berechnet \(vatAmount.germanAmount).")
        }
        if grandTotal != statedGrandTotal {
            problems.append("Endbetrag laut PDF \(statedGrandTotal.germanAmount), berechnet \(grandTotal.germanAmount).")
        }
        if !problems.isEmpty { throw InvoiceError.inconsistent(problems) }
    }
}

public struct InvoiceLine: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Leistung mit Umsatzsteuer (Kategorie S).
        case service
        /// Durchlaufender Posten ohne Umsatzsteuer (Kategorie E), z. B. Amtsgebühren.
        case disbursement
    }

    public enum Unit: String, Sendable, Equatable {
        case hour = "HUR"
        case piece = "C62"
    }

    public var id: Int
    public var kind: Kind
    public var name: String
    public var description: String
    public var quantity: Decimal
    public var unit: Unit
    public var unitPrice: Decimal
    public var amount: Decimal
}

public enum InvoiceError: LocalizedError, Equatable {
    case unreadablePDF
    case missingField(String)
    case unparsable(field: String, value: String)
    case inconsistent([String])

    public var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            return "Das PDF konnte nicht gelesen werden."
        case .missingField(let field):
            return "Im PDF wurde „\(field)“ nicht gefunden."
        case .unparsable(let field, let value):
            return "„\(field)“ konnte nicht gelesen werden: \(value)"
        case .inconsistent(let problems):
            return "Die Beträge im PDF sind nicht stimmig:\n" + problems.map { "• " + $0 }.joined(separator: "\n")
        }
    }
}
