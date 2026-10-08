import Foundation
import PDFKit

public struct ParseResult: Sendable {
    public var invoice: Invoice
    /// Hinweise, die keine Fehler sind, z. B. ein abweichender Stundensatz.
    public var warnings: [String]
}

/// Liest die variablen Rechnungsdaten aus einer mit LibreOffice erzeugten Rechnung.
public struct InvoiceParser {
    public let config: InvoiceConfig

    public init(config: InvoiceConfig) {
        self.config = config
    }

    public func parse(pdfAt url: URL) throws -> ParseResult {
        guard let pdf = try? Data(contentsOf: url), let document = PDFDocument(data: pdf) else {
            throw InvoiceError.unreadablePDF
        }
        try ZUGFeRDEmbedder.validatePDFa3(pdf)
        let lines = Self.textLines(of: document)
        var result = try parse(lines: lines)
        try readParties(from: document, lines: lines, invoice: &result.invoice)
        return result
    }

    // MARK: - Text nach Position

    /// Liefert den Text der ersten Seite zeilenweise in Lesereihenfolge.
    /// PDFKit gibt Textstücke nicht immer in der richtigen Reihenfolge zurück
    /// (z. B. stehen Beträge am Zeilenende sonst ganz unten). Deshalb werden
    /// die Stücke nach ihrer y-Position zu Zeilen gruppiert und nach x sortiert.
    public static func textLines(of document: PDFDocument) -> [String] {
        guard let page = document.page(at: 0) else { return [] }
        let fragments = positionedLines(on: page)
        var rows: [[Fragment]] = []
        for fragment in fragments.sorted(by: { $0.y > $1.y }) {
            if let last = rows.last?.first, abs(last.y - fragment.y) < 2 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            let ordered = row.sorted { $0.x < $1.x }
            guard ordered.contains(where: { Self.hasSpacedGlyphs($0.text) }) else {
                return ordered.map(\.text)
                    .joined(separator: " ")
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            }

            let joined = ordered.enumerated().map { index, fragment in
                let separator: String
                if index == 0 || fragment.x - ordered[index - 1].maxX <= 2 {
                    separator = ""
                } else {
                    separator = " "
                }
                return separator + Self.normalizeGlyphSpacing(fragment.text)
            }.joined()
            return joined
                .replacingOccurrences(of: #"\s+([:.,;])"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"(?<=[A-Za-zÄÖÜäöü]\.)(?=\d{4})"#, with: " ", options: .regularExpression)
        }
    }

    private struct Fragment { var text: String; var x: CGFloat; var y: CGFloat; var maxX: CGFloat }

    private static func positionedLines(on page: PDFPage) -> [Fragment] {
        guard let selection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        return selection.selectionsByLine().compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let bounds = line.bounds(for: page)
            return Fragment(text: text, x: bounds.minX, y: bounds.minY, maxX: bounds.maxX)
        }
    }

    private static func hasSpacedGlyphs(_ text: String) -> Bool {
        text.range(of: #"(?:[\p{L}\d]\s+){3,}[\p{L}\d]"#, options: .regularExpression) != nil
    }

    static func normalizeGlyphSpacing(_ text: String) -> String {
        return text.replacingOccurrences(
            of: #"(?<=[\p{L}\d])\s+(?=[\p{L}\d])"#,
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - Auswertung

    public func parse(lines: [String]) throws -> ParseResult {
        var warnings: [String] = []

        let number = try value(after: #"Rechnung Nr\.?\s*"#, in: lines, field: "Rechnung Nr.")
        let fileReference = try value(after: #"Ihr Zeichen:\s*"#, in: lines, field: "Ihr Zeichen")
        let ourReference = try? value(after: #"Unser Zeichen:\s*"#, in: lines, field: "Unser Zeichen")
        let dateText = try value(after: #".*,\s*den\s+"#, in: lines, field: "Rechnungsdatum")
        guard let issueDate = Self.parseDate(dateText) else {
            throw InvoiceError.unparsable(field: "Rechnungsdatum", value: dateText)
        }
        let periodText = try value(after: #"Leistungszeitraum:\s*"#, in: lines, field: "Leistungszeitraum")
        guard let period = Self.parsePeriod(periodText) else {
            throw InvoiceError.unparsable(field: "Leistungszeitraum", value: periodText)
        }
        let paymentText = lines.drop(while: { !$0.hasPrefix("Es wird um Überweisung") })
            .joined(separator: " ")
        guard let match = paymentText.firstMatch(of: /innerhalb\s+(?:von\s+)?(\d+)\s+Tagen?/) ,
              let paymentTermDays = Int(match.1)
        else {
            throw InvoiceError.missingField("Zahlungsfrist")
        }
        let contact = try? value(after: #"Patentreferent(?:in)?\s+"#, in: lines, field: "Patentreferent")

        // Positionsbereich: nach dem Leistungszeitraum bis zum Zahlungshinweis.
        guard let start = lines.firstIndex(where: { $0.hasPrefix("Leistungszeitraum") }) else {
            throw InvoiceError.missingField("Leistungszeitraum")
        }
        let end = lines.firstIndex(where: { $0.hasPrefix("Es wird um Überweisung") }) ?? lines.endIndex
        let body = lines[(start + 1)..<end].filter {
            !$0.hasPrefix("Lieferantennummer") && !$0.hasPrefix("Patentreferent")
        }

        var items: [InvoiceLine] = []
        var pendingText: [String] = []
        var netTotal: Decimal?
        var vatRate: Decimal?
        var vatAmount: Decimal?
        var grandTotal: Decimal?
        // Vor "Umsatzsteuer": Leistungen. Danach bis "Endbetrag": durchlaufende Posten.
        var afterVat = false

        for line in body {
            guard let (label, amount) = Self.splitAmount(line) else {
                pendingText.append(line)
                continue
            }
            if label.hasPrefix("Zwischensumme") {
                netTotal = amount
            } else if let match = label.firstMatch(of: /^Umsatzsteuer\s+(\d+(?:,\d+)?)\s*%/) {
                vatRate = Decimal(german: String(match.1))
                vatAmount = amount
                afterVat = true
            } else if label.hasPrefix("Endbetrag") {
                grandTotal = amount
            } else {
                let text = (pendingText + [label]).filter { !$0.isEmpty }.joined(separator: " ")
                pendingText = []
                var item = Self.makeLine(id: items.count + 1, text: text, amount: amount,
                                         kind: afterVat ? .disbursement : .service,
                                         defaultRate: config.hourlyRate)
                if item.unit == .hour, item.unitPrice != config.hourlyRate {
                    warnings.append("Position \(item.id): Stundensatz im PDF \(item.unitPrice.germanAmount) € weicht vom eingestellten Satz \(config.hourlyRate.germanAmount) € ab.")
                }
                item.id = items.count + 1
                items.append(item)
            }
        }

        guard let netTotal else { throw InvoiceError.missingField("Zwischensumme") }
        guard let vatRate, let vatAmount else { throw InvoiceError.missingField("Umsatzsteuer") }
        guard let grandTotal else { throw InvoiceError.missingField("Endbetrag") }

        let invoice = Invoice(
            number: number,
            issueDate: issueDate,
            paymentTermDays: paymentTermDays,
            fileReference: fileReference,
            ourReference: ourReference,
            billingPeriod: period,
            buyerContactName: contact,
            lines: items,
            vatRate: vatRate,
            statedNetTotal: netTotal,
            statedVatAmount: vatAmount,
            statedGrandTotal: grandTotal
        )
        try invoice.validate()
        return ParseResult(invoice: invoice, warnings: warnings)
    }

    private func readParties(from document: PDFDocument, lines: [String], invoice: inout Invoice) throws {
        guard let page = document.page(at: 0) else { throw InvoiceError.unreadablePDF }
        let fragments = Self.positionedLines(on: page)
        let normalized = lines.joined(separator: " ")

        guard let supplierAddress = fragments.first(where: {
            $0.text.contains("Frauenstr.") && $0.text.contains("80469")
        })?.text else {
            throw InvoiceError.missingField("Verkäuferdaten")
        }
        let addressParts = supplierAddress.split(whereSeparator: { $0 == "∙" || $0 == "·" }).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard addressParts.count == 3,
              let supplierLocation = addressParts[2].firstMatch(of: /^(\d{5})\s+(.+)$/)
        else {
            throw InvoiceError.missingField("Verkäuferadresse")
        }
        let supplierID = try? value(after: #"Lieferantennummer:\s*"#, in: lines, field: "Lieferantennummer")

        let vatID = Self.capture(#"USt-ID:\s*([A-Z]{2}[A-Z0-9]+)"#, in: normalized)
        let bic = Self.capture(#"BIC:\s*([A-Z0-9]+)"#, in: normalized)
        guard let iban = Self.capture(#"IBAN:\s*([A-Z]{2}[0-9A-Z ]+)"#, in: normalized), let bic else {
            throw InvoiceError.missingField("Bankverbindung")
        }

        let sellerContact = fragments
            .filter { $0.x > 300 && $0.text.contains("Univ.") }
            .compactMap { fragment -> String? in
                let firstColumn = fragment.text.components(separatedBy: ",").first ?? fragment.text
                let namePart = firstColumn.components(separatedBy: "Univ.").last ?? firstColumn
                let words = namePart.split(whereSeparator: \.isWhitespace)
                guard words.count >= 2 else { return nil }
                return words.suffix(2).joined(separator: " ")
            }
            .first
        let phoneText = fragments.first(where: { $0.x > 300 && $0.text.hasPrefix("Tel:") })?.text
        let phone = phoneText.flatMap { Self.capture(#"Tel:\s*([^;]+)"#, in: $0) }
        let email = fragments.first(where: { $0.x > 300 && $0.text.contains("@") })?.text
        invoice.seller = Invoice.Seller(
            id: supplierID,
            name: addressParts[0],
            contactName: sellerContact,
            phone: phone,
            email: email,
            street: addressParts[1],
            postcode: String(supplierLocation.1),
            city: String(supplierLocation.2),
            country: "DE",
            vatId: vatID
        )

        let leftColumn = fragments.filter { $0.x < 300 }.sorted { $0.y > $1.y }
        guard let addressY = fragments.first(where: { $0.text == supplierAddress })?.y,
              let electronicIndex = leftColumn.firstIndex(where: { $0.text.localizedCaseInsensitiveContains("nur in elektronischer Form") })
        else {
            throw InvoiceError.missingField("Käuferadresse")
        }
        let recipient = leftColumn[..<electronicIndex].filter { $0.y < addressY }.map(\.text)
        guard let postcodeIndex = recipient.firstIndex(where: { $0.firstMatch(of: /^\d{5}\s+.+$/) != nil }),
              let buyerName = recipient.first,
              let buyerAddress = recipient[postcodeIndex].firstMatch(of: /^(\d{5})\s+(.+)$/)
        else {
            throw InvoiceError.missingField("Käuferdaten")
        }
        var buyerAddressLines = Array(recipient.dropFirst().prefix(postcodeIndex - 1))
        if let contact = invoice.buyerContactName {
            buyerAddressLines.removeAll { $0 == contact }
        }
        invoice.buyer = Invoice.Buyer(
            id: nil,
            name: buyerName,
            email: nil,
            addressLines: buyerAddressLines,
            postcode: String(buyerAddress.1),
            city: String(buyerAddress.2),
            country: "DE",
            vatId: nil
        )

        guard lines.contains(where: { $0.hasPrefix("Es wird um Überweisung") }) else {
            throw InvoiceError.missingField("Zahlungsbedingungen")
        }
        let paymentDays = invoice.paymentTermDays
        invoice.payment = Invoice.Payment(
            iban: iban.filter { !$0.isWhitespace },
            bic: bic,
            accountHolder: nil,
            terms: "Zahlbar innerhalb von \(paymentDays) Tagen nach Erhalt der Rechnung ohne Abzug."
        )
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
          guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Hilfsfunktionen

    private func value(after pattern: String, in lines: [String], field: String) throws -> String {
        let regex = try NSRegularExpression(pattern: "^" + pattern + "(\\S.*?)\\s*$")
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let m = regex.firstMatch(in: line, range: range), let r = Range(m.range(at: 1), in: line) {
                // Rechts danebenstehende Angaben (z. B. Datum neben "Ihr Zeichen") abschneiden.
                return Self.leftColumn(String(line[r]))
            }
        }
        throw InvoiceError.missingField(field)
    }

    /// "Ihr Zeichen: 26-1884 München, den …" → "26-1884"
    private static func leftColumn(_ text: String) -> String {
        for marker in [" München, den ", " Seite "] {
            if let r = text.range(of: marker) { return String(text[..<r.lowerBound]) }
        }
        return text
    }

    /// Trennt "Zwischensumme EUR 2.025,00" in ("Zwischensumme", 2025.00).
    static func splitAmount(_ line: String) -> (String, Decimal)? {
        guard let m = line.firstMatch(of: /^(.*?)\s*EUR\s+(\d{1,3}(?:\.\d{3})*,\d{2})$/),
              let amount = Decimal(german: String(m.2))
        else { return nil }
        return (String(m.1), amount)
    }

    static func makeLine(id: Int, text: String, amount: Decimal, kind: InvoiceLine.Kind, defaultRate: Decimal) -> InvoiceLine {
        let name = text.split(separator: ";", maxSplits: 1).first.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? text

        // "7,5 abrechenbare Stunden à 270 €"
        if kind == .service,
           let m = text.firstMatch(of: /(\d+(?:,\d+)?)\s+(?:abrechenbare\s+)?(?:Stunden|Stunde|Std\.)(?:\s+à\s+(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?)\s*(?:€|EUR))?/),
           let hours = Decimal(german: String(m.1)) {
            let rate = m.2.flatMap { Decimal(german: String($0)) } ?? defaultRate
            return InvoiceLine(id: id, kind: kind, name: name, description: text,
                               quantity: hours, unit: .hour, unitPrice: rate, amount: amount)
        }
        return InvoiceLine(id: id, kind: kind, name: name, description: text,
                           quantity: 1, unit: .piece, unitPrice: amount, amount: amount)
    }

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    /// "28. September 2026" oder "04.09.2020"
    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for format in ["d. MMMM yyyy", "dd.MM.yyyy", "d.M.yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static let months: [(prefix: String, month: Int)] = [
        ("jan", 1), ("feb", 2), ("mär", 3), ("mrz", 3), ("apr", 4), ("mai", 5), ("jun", 6),
        ("jul", 7), ("aug", 8), ("sep", 9), ("okt", 10), ("nov", 11), ("dez", 12),
    ]

    private static func month(_ text: String) -> Int? {
        let t = text.lowercased()
        return months.first { t.hasPrefix($0.prefix) }?.month
    }

    /// "Sep. 2026", "Sep 2020", "September 2026" oder "Aug.–Sep. 2026" → ganze Kalendermonate.
    static func parsePeriod(_ text: String) -> DateInterval? {
        guard let m = text.firstMatch(of: /^([A-Za-zÄÖÜäöü]+)\.?(?:\s*[-–]\s*([A-Za-zÄÖÜäöü]+)\.?)?\s+(\d{4})$/),
              let year = Int(m.3),
              let first = month(String(m.1))
        else { return nil }
        let last = m.2.flatMap { month(String($0)) } ?? first
        guard last >= first,
              let start = calendar.date(from: DateComponents(year: year, month: first, day: 1)),
              let lastMonthStart = calendar.date(from: DateComponents(year: year, month: last, day: 1)),
              let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: lastMonthStart)
        else { return nil }
        return DateInterval(start: start, end: end)
    }
}
