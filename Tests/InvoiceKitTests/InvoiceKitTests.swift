import Foundation
import CoreGraphics
import PDFKit
import Testing
@testable import InvoiceKit

private let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func reference(_ name: String) -> URL {
    projectRoot.appendingPathComponent("Referenzen/\(name)-re.pdf")
}

private func config() throws -> InvoiceConfig {
    try InvoiceConfig.load(from: projectRoot.appendingPathComponent("Config/config.json"))
}

private func ymd(_ date: Date) -> String {
    XMLBuilder.format102(date)
}

@Suite("PDF auslesen")
struct ParserTests {
    @Test func bmwStundenrechnung() throws {
        let result = try InvoiceParser(config: config()).parse(pdfAt: reference("BMW3090"))
        let inv = result.invoice
        #expect(inv.number == "20260274")
        #expect(ymd(inv.issueDate) == "20260928")
        #expect(inv.paymentTermDays == 20)
        #expect(inv.fileReference == "26-1884")
        #expect(inv.ourReference == "BMW3090")
        #expect(ymd(inv.billingPeriod.start) == "20260901")
        #expect(ymd(inv.billingPeriod.end) == "20260930")
        #expect(inv.buyerContactName == "Bernhard Göbel")
        #expect(inv.seller?.id == "125593-10")
        #expect(inv.seller?.name == "Zweibrücken IP")
        #expect(inv.seller?.vatId == "DE258629650")
        #expect(inv.buyer?.name == "BMW AG")
        #expect(inv.buyer?.addressLines == ["Patentabteilung AJ-53"])
        #expect(inv.buyer?.postcode == "80788")
        #expect(inv.payment?.iban == "DE19120300001013773757")
        #expect(inv.payment?.bic == "BYLADEM1001")
        #expect(inv.lines.count == 1)
        let line = try #require(inv.lines.first)
        #expect(line.unit == .hour)
        #expect(line.quantity == Decimal(string: "7.5"))
        #expect(line.unitPrice == 270)
        #expect(line.amount == 2025)
        #expect(line.name == "Besprechen der Erfindung mit dem Erfinder per Videokonferenz")
        #expect(line.description.hasSuffix("7,5 abrechenbare Stunden à 270 €"))
        #expect(inv.vatRate == 19)
        #expect(inv.vatAmount == Decimal(string: "384.75"))
        #expect(inv.grandTotal == Decimal(string: "2409.75"))
        #expect(result.warnings.isEmpty)
    }

    @Test func durchlaufendePosten() throws {
        let inv = try InvoiceParser(config: config()).parse(pdfAt: reference("RAK1742")).invoice
        #expect(inv.lines.map(\.kind) == [.service, .service, .disbursement, .disbursement])
        #expect(inv.lines.map(\.amount) == [2200, 300, 60, 350])
        #expect(inv.lines[1].description == "Übernahme der Vertretung vor dem DPMA und Einreichen der Anmeldung")
        #expect(inv.taxableTotal == 2500)
        #expect(inv.disbursementTotal == 410)
        #expect(inv.vatAmount == 400)
        #expect(inv.grandTotal == 3310)
        #expect(inv.buyerContactName == nil)
        #expect(inv.buyer?.name == "Viktor Rakoczi")
        #expect(inv.buyer?.addressLines == ["Sommerberg 10"])
        #expect(inv.seller?.id == nil)
    }

    @Test func abweichenderStundensatzErzeugtWarnung() throws {
        var cfg = try config()
        cfg.hourlyRate = 250
        let result = try InvoiceParser(config: cfg).parse(pdfAt: reference("BMW3090"))
        #expect(result.warnings.count == 1)
        #expect(result.invoice.lines[0].unitPrice == 270)
    }

    @Test func falscheSummeWirdErkannt() throws {
        var lines = InvoiceParser.textLines(of: PDFDocument(url: reference("BMW3090"))!)
        let index = try #require(lines.firstIndex { $0.hasPrefix("Endbetrag") })
        lines[index] = "Endbetrag EUR 2.409,76"
        #expect(throws: InvoiceError.self) {
            try InvoiceParser(config: config()).parse(lines: lines)
        }
    }

    @Test(arguments: [
        ("Okt. 2026", "20261001", "20261031"),
        ("Sep. 2026", "20260901", "20260930"),
        ("Sep 2020", "20200901", "20200930"),
        ("Februar 2028", "20280201", "20280229"),
        ("Mär. 2026", "20260301", "20260331"),
        ("Aug.–Sep. 2026", "20260801", "20260930"),
    ])
    func leistungszeitraum(text: String, start: String, end: String) throws {
        let period = try #require(InvoiceParser.parsePeriod(text))
        #expect(ymd(period.start) == start)
        #expect(ymd(period.end) == end)
    }

    @Test func pdfGlyphSpacing() {
        #expect(InvoiceParser.normalizeGlyphSpacing("L e i s t u n g s z e i t r") == "Leistungszeitr")
        #expect(InvoiceParser.normalizeGlyphSpacing("a u") == "au")
        #expect(InvoiceParser.normalizeGlyphSpacing("O k t .") == "Okt .")
        #expect(InvoiceParser.normalizeGlyphSpacing("2 0 2 6") == "2026")
    }

    @Test func pdfa3Metadatenpruefung() throws {
        try ZUGFeRDEmbedder.validatePDFa3XMP("<pdfaid:part>3</pdfaid:part>")
        try ZUGFeRDEmbedder.validatePDFa3XMP("<x pdfaid:part=\"3\"/>")
        #expect(throws: ZUGFeRDEmbedder.Error.notPDFA3) {
            try ZUGFeRDEmbedder.validatePDFa3XMP("<pdfaid:part>2</pdfaid:part>")
        }
    }

    @Test func nichtPDFA3WirdBeimLadenAbgelehnt() throws {
        let buffer = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try #require(CGDataConsumer(data: buffer as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("non-pdfa-\(UUID().uuidString).pdf")
        try (buffer as Data).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ZUGFeRDEmbedder.Error.notPDFA3) {
            try InvoiceParser(config: config()).parse(pdfAt: url)
        }
    }

    @Test func datumsformate() {
        #expect(InvoiceParser.parseDate("28. September 2026").map(ymd) == "20260928")
        #expect(InvoiceParser.parseDate("04.09.2020").map(ymd) == "20200904")
        #expect(InvoiceParser.parseDate("1. März 2027").map(ymd) == "20270301")
    }

    @Test func betragszeile() {
        let (label, amount) = InvoiceParser.splitAmount("Umsatzsteuer 19 % EUR 1.384,75")!
        #expect(label == "Umsatzsteuer 19 %")
        #expect(amount == Decimal(string: "1384.75"))
        #expect(InvoiceParser.splitAmount("Bearbeiter: Herr Birnbach; 7,5 Stunden à 270 €") == nil)
    }
}

@Suite("XML und Einbettung")
struct GeneratorTests {
    @Test func kundenvorgabenImXML() throws {
        let cfg = try config()
        let inv = try InvoiceParser(config: cfg).parse(pdfAt: reference("BMW3090")).invoice
        let xml = CIIWriter(config: cfg).xml(for: inv)
        let doc = try XMLDocument(xmlString: xml)
        func value(_ path: String) throws -> String? {
            try doc.nodes(forXPath: path).first?.stringValue
        }
        let agreement = "/*:CrossIndustryInvoice/*:SupplyChainTradeTransaction/*:ApplicableHeaderTradeAgreement"
        #expect(try value("/*:CrossIndustryInvoice/*:ExchangedDocumentContext/*:BusinessProcessSpecifiedDocumentContextParameter/*:ID") == CIIWriter.businessProcess)
        #expect(try value("/*:CrossIndustryInvoice/*:ExchangedDocumentContext/*:GuidelineSpecifiedDocumentContextParameter/*:ID") == CIIWriter.guideline)
        #expect(try value("\(agreement)/*:BuyerReference") == "26-1884")
        #expect(cfg.buyerID == "A1")
        #expect(cfg.supplierID == "12559310")
        #expect(cfg.buyerEmail == "patentabteilung@bmw.de")
        #expect(try value("\(agreement)/*:BuyerTradeParty/*:ID") == "A1")
        #expect(try value("\(agreement)/*:BuyerTradeParty/*:Name") == "BMW AG")
        #expect(try value("\(agreement)/*:BuyerTradeParty/*:PostalTradeAddress/*:LineOne") == "Patentabteilung AJ-53")
        #expect(try value("\(agreement)/*:BuyerTradeParty/*:URIUniversalCommunication/*:URIID") == "bmw.en16931@quibiqedocservice.de")
        #expect(try value("\(agreement)/*:BuyerTradeParty/*:SpecifiedTaxRegistration/*:ID") == nil)
        #expect(try value("\(agreement)/*:SellerTradeParty/*:ID") == "12559310")
        #expect(try value("\(agreement)/*:SellerTradeParty/*:Name") == "Zweibrücken IP")
        #expect(try value("\(agreement)/*:SellerTradeParty/*:URIUniversalCommunication/*:URIID") == "mail@zweibruecken-ip.de")
        let settlement = "/*:CrossIndustryInvoice/*:SupplyChainTradeTransaction/*:ApplicableHeaderTradeSettlement"
        #expect(try value("\(settlement)/*:SpecifiedTradeSettlementPaymentMeans/*:PayeePartyCreditorFinancialAccount/*:IBANID") == "DE19120300001013773757")
        #expect(try value("\(settlement)/*:SpecifiedTradeSettlementPaymentMeans/*:PayeeSpecifiedCreditorFinancialInstitution/*:BICID") == "BYLADEM1001")
        #expect(try value("/*:CrossIndustryInvoice/*:ExchangedDocument/*:IncludedNote/*:Content") == "REF. 26-1884")
        #expect(try value("/*:CrossIndustryInvoice/*:SupplyChainTradeTransaction/*:ApplicableHeaderTradeSettlement/*:SpecifiedTradePaymentTerms/*:DueDateDateTime/*:DateTimeString") == "20261018")
    }

    @Test func lieferantennummerAusVoreinstellungenWirdVerwendet() throws {
        var cfg = try config()
        cfg.supplierID = "12559310"
        let inv = try InvoiceParser(config: cfg).parse(pdfAt: reference("BMW3090")).invoice
        let xml = CIIWriter(config: cfg).xml(for: inv)
        let doc = try XMLDocument(xmlString: xml)
        let value = try doc.nodes(forXPath: "/*:CrossIndustryInvoice/*:SupplyChainTradeTransaction/*:ApplicableHeaderTradeAgreement/*:SellerTradeParty/*:ID").first?.stringValue
        #expect(value == "12559310")
    }

    @Test func einbettenBehaeltOriginal() throws {
        let source = reference("RAK1742")
        let parsed = try InvoiceParser(config: config()).parse(pdfAt: source)
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(parsed.invoice.number)-RAK1742-\(UUID().uuidString).pdf")
        try Data(contentsOf: source).write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }

        let original = try Data(contentsOf: input)
        let result = try EInvoiceGenerator(config: config()).generate(from: input, parsed: parsed)
        #expect(result.pdf.prefix(original.count) == original)

        let doc = try #require(PDFDocument(data: result.pdf))
        #expect(doc.pageCount == 1)
        #expect(doc.string == PDFDocument(data: original)?.string)

        let tail = String(decoding: result.pdf.suffix(from: original.count), as: UTF8.self)
        #expect(tail.contains("/AFRelationship/Alternative"))
        #expect(tail.contains("<fx:ConformanceLevel>EN 16931</fx:ConformanceLevel>"))
    }

    @Test func dateinameOhneRechnungsnummerWirdAbgelehnt() throws {
        let source = reference("BMW3090")
        let parsed = try InvoiceParser(config: config()).parse(pdfAt: source)
        let error = InvoiceError.sourceFileNameDoesNotContainInvoiceNumber(
            fileName: "BMW3090-re",
            invoiceNumber: parsed.invoice.number
        )

        #expect(throws: error) {
            try EInvoiceGenerator(config: config()).generate(from: source, parsed: parsed)
        }
    }

    @Test func zweimalEinbettenWirdAbgelehnt() throws {
        let cfg = try config()
        let source = reference("BMW3090")
        let parsed = try InvoiceParser(config: cfg).parse(pdfAt: source)
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(parsed.invoice.number)-BMW3090-\(UUID().uuidString).pdf")
        try Data(contentsOf: source).write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }

        let first = try EInvoiceGenerator(config: cfg).generate(from: input, parsed: parsed).pdf
        #expect(throws: ZUGFeRDEmbedder.Error.alreadyEInvoice) {
            try ZUGFeRDEmbedder().embed(xml: Data("<x/>".utf8), into: first)
        }
    }
}
