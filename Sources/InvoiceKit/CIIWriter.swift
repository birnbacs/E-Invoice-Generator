import Foundation

/// Erzeugt das ZUGFeRD-2.1-XML (UN/CEFACT CII, Profil EN 16931).
/// Die Reihenfolge der Elemente ist durch das XML-Schema vorgegeben.
public struct CIIWriter {
    public static let guideline = "urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0"
    public static let businessProcess = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"
    public static let fileName = "factur-x.xml"

    public let config: InvoiceConfig

    public init(config: InvoiceConfig) {
        self.config = config
    }

    public func xml(for invoice: Invoice) -> String {
        let c = config
        let cur = c.currency
        var x = XMLBuilder()

        x.raw(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        x.open("rsm:CrossIndustryInvoice", attributes: [
            ("xmlns:rsm", "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"),
            ("xmlns:qdt", "urn:un:unece:uncefact:data:standard:QualifiedDataType:100"),
            ("xmlns:ram", "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"),
            ("xmlns:udt", "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"),
        ])

        x.open("rsm:ExchangedDocumentContext")
        x.open("ram:BusinessProcessSpecifiedDocumentContextParameter")
        x.element("ram:ID", Self.businessProcess)                          // BT-23
        x.close()
        x.open("ram:GuidelineSpecifiedDocumentContextParameter")
        x.element("ram:ID", Self.guideline)                                 // BT-24
        x.close()
        x.close()

        x.open("rsm:ExchangedDocument")
        x.element("ram:ID", invoice.number)                                   // BT-1
        x.element("ram:TypeCode", "380")                                      // BT-3 Handelsrechnung
        x.date("ram:IssueDateTime", invoice.issueDate)                       // BT-2
        x.open("ram:IncludedNote")
        x.element("ram:Content", c.referenceNotePrefix + invoice.fileReference) // BT-22
        x.close()
        x.close()

        x.open("rsm:SupplyChainTradeTransaction")

        for line in invoice.lines {
            x.open("ram:IncludedSupplyChainTradeLineItem")
            x.open("ram:AssociatedDocumentLineDocument")
            x.element("ram:LineID", String(line.id))                          // BT-126
            x.close()
            x.open("ram:SpecifiedTradeProduct")
            x.element("ram:Name", line.name)                                  // BT-153
            x.element("ram:Description", line.description)                    // BT-154
            x.close()
            x.open("ram:SpecifiedLineTradeAgreement")
            x.open("ram:NetPriceProductTradePrice")
            x.element("ram:ChargeAmount", line.unitPrice.xmlAmount)           // BT-146
            x.close()
            x.close()
            x.open("ram:SpecifiedLineTradeDelivery")
            x.element("ram:BilledQuantity", line.quantity.xmlQuantity,        // BT-129/130
                      attributes: [("unitCode", line.unit.rawValue)])
            x.close()
            x.open("ram:SpecifiedLineTradeSettlement")
            x.open("ram:ApplicableTradeTax")
            x.element("ram:TypeCode", "VAT")
            x.element("ram:CategoryCode", category(line.kind))                // BT-151
            x.element("ram:RateApplicablePercent", rate(line.kind, invoice).xmlAmount) // BT-152
            x.close()
            x.open("ram:SpecifiedTradeSettlementLineMonetarySummation")
            x.element("ram:LineTotalAmount", line.amount.xmlAmount)           // BT-131
            x.close()
            x.close()
            x.close()
        }

        x.open("ram:ApplicableHeaderTradeAgreement")
    x.element("ram:BuyerReference", invoice.fileReference)               // BT-10
        if let seller = invoice.seller {
            x.open("ram:SellerTradeParty")
            let sellerID = c.supplierID.isEmpty ? seller.id : c.supplierID
            if let id = sellerID { x.element("ram:ID", id) }                 // BT-29
            x.element("ram:Name", seller.name)                                // BT-27
            if seller.contactName != nil || seller.phone != nil || seller.email != nil {
                x.open("ram:DefinedTradeContact")
                if let contactName = seller.contactName { x.element("ram:PersonName", contactName) }
                if let phone = seller.phone {
                    x.open("ram:TelephoneUniversalCommunication")
                    x.element("ram:CompleteNumber", phone)                    // BT-42
                    x.close()
                }
                if let email = seller.email {
                    x.open("ram:EmailURIUniversalCommunication")
                    x.element("ram:URIID", email)                             // BT-43
                    x.close()
                }
                x.close()
            }
            x.address(postcode: seller.postcode, lines: [seller.street], city: seller.city, country: seller.country)
            if let email = seller.email {
                x.open("ram:URIUniversalCommunication")
                x.element("ram:URIID", email, attributes: [("schemeID", "EM")]) // BT-34
                x.close()
            }
            if let vatId = seller.vatId {
                x.open("ram:SpecifiedTaxRegistration")
                x.element("ram:ID", vatId, attributes: [("schemeID", "VA")]) // BT-31
                x.close()
            }
            x.close()
        }

        if let buyer = invoice.buyer {
            x.open("ram:BuyerTradeParty")
            if !c.buyerID.isEmpty { x.element("ram:ID", c.buyerID) }          // BT-46
            x.element("ram:Name", buyer.name)                                 // BT-44
            if let contactName = invoice.buyerContactName {
                x.open("ram:DefinedTradeContact")
                x.element("ram:PersonName", contactName)                      // BT-56
                x.close()
            }
            x.address(postcode: buyer.postcode, lines: buyer.addressLines, city: buyer.city, country: buyer.country)
            let buyerEmail = c.buyerSMTP.isEmpty ? (buyer.email ?? c.buyerEmail) : c.buyerSMTP
            if !buyerEmail.isEmpty {
                x.open("ram:URIUniversalCommunication")
                x.element("ram:URIID", buyerEmail, attributes: [("schemeID", "EM")]) // BT-49
                x.close()
            }
            if let vatId = buyer.vatId {
                x.open("ram:URIUniversalCommunication")
                x.element("ram:URIID", vatId, attributes: [("schemeID", "9930")]) // BT-49
                x.close()
                x.open("ram:SpecifiedTaxRegistration")
                x.element("ram:ID", vatId, attributes: [("schemeID", "VA")]) // BT-48
                x.close()
            }
            x.close()
        }
        x.close()

        x.open("ram:ApplicableHeaderTradeDelivery")
        x.open("ram:ActualDeliverySupplyChainEvent")
        x.date("ram:OccurrenceDateTime", invoice.billingPeriod.end)          // BT-72: Ende des Leistungszeitraums
        x.close()
        x.close()

        x.open("ram:ApplicableHeaderTradeSettlement")
        x.element("ram:PaymentReference", "Rechnung \(invoice.number)")      // BT-83
        x.element("ram:InvoiceCurrencyCode", cur)                             // BT-5
        if let payment = invoice.payment {
            x.open("ram:SpecifiedTradeSettlementPaymentMeans")
            x.element("ram:TypeCode", "58")                                   // BT-81 SEPA-Überweisung
            x.open("ram:PayeePartyCreditorFinancialAccount")
            x.element("ram:IBANID", payment.iban)                              // BT-84
            if let accountHolder = payment.accountHolder {
                x.element("ram:AccountName", accountHolder)                    // BT-85
            }
            x.close()
            x.open("ram:PayeeSpecifiedCreditorFinancialInstitution")
            x.element("ram:BICID", payment.bic)                               // BT-86
            x.close()
            x.close()
        }

        // BG-23: Aufschlüsselung der Umsatzsteuer je Kategorie
        x.open("ram:ApplicableTradeTax")
        x.element("ram:CalculatedAmount", invoice.vatAmount.xmlAmount)
        x.element("ram:TypeCode", "VAT")
        x.element("ram:BasisAmount", invoice.taxableTotal.xmlAmount)
        x.element("ram:CategoryCode", "S")
        x.element("ram:RateApplicablePercent", invoice.vatRate.xmlAmount)
        x.close()
        if !invoice.disbursementLines.isEmpty {
            x.open("ram:ApplicableTradeTax")
            x.element("ram:CalculatedAmount", Decimal(0).xmlAmount)
            x.element("ram:TypeCode", "VAT")
            x.element("ram:ExemptionReason", c.disbursementExemptionReason)   // BT-120
            x.element("ram:BasisAmount", invoice.disbursementTotal.xmlAmount)
            x.element("ram:CategoryCode", "E")
            x.element("ram:RateApplicablePercent", Decimal(0).xmlAmount)
            x.close()
        }

        x.open("ram:BillingSpecifiedPeriod")                                  // BG-14
        x.date("ram:StartDateTime", invoice.billingPeriod.start)
        x.date("ram:EndDateTime", invoice.billingPeriod.end)
        x.close()

        if let payment = invoice.payment {
            x.open("ram:SpecifiedTradePaymentTerms")
            x.element("ram:Description", payment.terms)                       // BT-20
            x.date("ram:DueDateDateTime", dueDate(for: invoice))              // BT-9
            x.close()
        }

        x.open("ram:SpecifiedTradeSettlementHeaderMonetarySummation")
        x.element("ram:LineTotalAmount", invoice.lineTotal.xmlAmount)         // BT-106
        x.element("ram:TaxBasisTotalAmount", invoice.lineTotal.xmlAmount)     // BT-109
        x.element("ram:TaxTotalAmount", invoice.vatAmount.xmlAmount, attributes: [("currencyID", cur)]) // BT-110
        x.element("ram:GrandTotalAmount", invoice.grandTotal.xmlAmount)       // BT-112
        x.element("ram:DuePayableAmount", invoice.grandTotal.xmlAmount)       // BT-115
        x.close()

        x.close() // ApplicableHeaderTradeSettlement
        x.close() // SupplyChainTradeTransaction
        x.close() // CrossIndustryInvoice
        return x.output
    }

    private func category(_ kind: InvoiceLine.Kind) -> String {
        kind == .service ? "S" : "E"
    }

    private func rate(_ kind: InvoiceLine.Kind, _ invoice: Invoice) -> Decimal {
        kind == .service ? invoice.vatRate : 0
    }

    private func dueDate(for invoice: Invoice) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar.date(byAdding: .day, value: invoice.paymentTermDays, to: invoice.issueDate) ?? invoice.issueDate
    }
}

/// Minimaler XML-Schreiber mit Einrückung und Escaping.
struct XMLBuilder {
    private(set) var output = ""
    private var stack: [String] = []

    private var indent: String { String(repeating: "  ", count: stack.count) }

    mutating func raw(_ text: String) {
        output += text + "\n"
    }

    mutating func open(_ name: String, attributes: [(String, String)] = []) {
        output += indent + "<" + name + Self.attributes(attributes) + ">\n"
        stack.append(name)
    }

    mutating func close() {
        let name = stack.removeLast()
        output += indent + "</" + name + ">\n"
    }

    mutating func element(_ name: String, _ value: String, attributes: [(String, String)] = []) {
        output += indent + "<" + name + Self.attributes(attributes) + ">" + Self.escape(value) + "</" + name + ">\n"
    }

    mutating func date(_ name: String, _ date: Date) {
        open(name)
        element("udt:DateTimeString", Self.format102(date), attributes: [("format", "102")])
        close()
    }

    mutating func address(postcode: String, lines: [String], city: String, country: String) {
        open("ram:PostalTradeAddress")
        element("ram:PostcodeCode", postcode)
        for (index, line) in lines.prefix(3).enumerated() where !line.isEmpty {
            element(index == 0 ? "ram:LineOne" : "ram:LineTwo", line)
        }
        element("ram:CityName", city)
        element("ram:CountryID", country)
        close()
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func attributes(_ attrs: [(String, String)]) -> String {
        attrs.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
    }

    /// Datumsformat 102: JJJJMMTT
    static func format102(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }
}
