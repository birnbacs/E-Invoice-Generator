import Foundation

/// Gesamter Ablauf: PDF lesen → XML erzeugen → XML ins PDF einbetten.
public struct EInvoiceGenerator {
    public let config: InvoiceConfig

    public init(config: InvoiceConfig) {
        self.config = config
    }

    public struct Result {
        public var parse: ParseResult
        public var xml: String
        public var pdf: Data
    }

    public func generate(from input: URL, modificationDate: Date = Date()) throws -> Result {
        let parsed = try InvoiceParser(config: config).parse(pdfAt: input)
        return try generate(from: input, parsed: parsed, modificationDate: modificationDate)
    }

    /// Variante für die App: Die (ggf. geprüften) Daten werden übergeben.
    public func generate(from input: URL, parsed: ParseResult, modificationDate: Date = Date()) throws -> Result {
        try parsed.invoice.validate()
        let xml = CIIWriter(config: config).xml(for: parsed.invoice)
        let original = try Data(contentsOf: input)
        let pdf = try ZUGFeRDEmbedder().embed(xml: Data(xml.utf8), into: original, modificationDate: modificationDate)
        return Result(parse: parsed, xml: xml, pdf: pdf)
    }

    /// Vorgeschlagener Dateiname: "BMW3090-re.pdf" → "BMW3090-re-zugferd.pdf"
    public static func defaultOutputURL(for input: URL) -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        return input.deletingLastPathComponent().appendingPathComponent(base + "-zugferd.pdf")
    }
}
