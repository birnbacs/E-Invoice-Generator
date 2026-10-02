import Foundation
import InvoiceKit

let usage = """
Verwendung: invoice-cli <rechnung.pdf> [Optionen]

Optionen:
  -o, --output <datei.pdf>   Ziel-PDF (Standard: <name>-zugferd.pdf neben dem Original)
  -c, --config <datei.json>  Konfiguration (Standard: Config/config.json)
  --xml <datei.xml>          XML zusätzlich als Datei speichern
  --dry-run                  Nur auslesen und anzeigen, nichts schreiben
"""

var args = Array(CommandLine.arguments.dropFirst())
var input: URL?
var output: URL?
var configURL = URL(fileURLWithPath: "Config/config.json")
var xmlURL: URL?
var dryRun = false

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-o", "--output":
        guard !args.isEmpty else { fail(usage) }
        output = URL(fileURLWithPath: args.removeFirst())
    case "-c", "--config":
        guard !args.isEmpty else { fail(usage) }
        configURL = URL(fileURLWithPath: args.removeFirst())
    case "--xml":
        guard !args.isEmpty else { fail(usage) }
        xmlURL = URL(fileURLWithPath: args.removeFirst())
    case "--dry-run":
        dryRun = true
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        if arg.hasPrefix("-") || input != nil { fail(usage) }
        input = URL(fileURLWithPath: arg)
    }
}

guard let input else { fail(usage) }

do {
    let config = try InvoiceConfig.load(from: configURL)
    let generator = EInvoiceGenerator(config: config)
    let parsed = try InvoiceParser(config: config).parse(pdfAt: input)
    let inv = parsed.invoice

    let df = DateFormatter()
    df.dateFormat = "dd.MM.yyyy"
    print("Rechnung Nr.:      \(inv.number)")
    print("Datum:             \(df.string(from: inv.issueDate))")
    print("Aktenzeichen:      \(inv.fileReference)  →  BT-22 „\(config.referenceNotePrefix)\(inv.fileReference)“")
    print("Unser Zeichen:     \(inv.ourReference ?? "–")")
    print("Leistungszeitraum: \(df.string(from: inv.billingPeriod.start)) – \(df.string(from: inv.billingPeriod.end))")
    print("Ansprechpartner:   \(inv.buyerContactName ?? "–")")
    for line in inv.lines {
        let tax = line.kind == .service ? "USt \(inv.vatRate.xmlQuantity) %" : "durchlaufend"
        print("  [\(line.id)] \(line.quantity.xmlQuantity) \(line.unit.rawValue) × \(line.unitPrice.germanAmount) = \(line.amount.germanAmount) EUR (\(tax))")
        print("      \(line.description)")
    }
    print("Netto \(inv.taxableTotal.germanAmount) + USt \(inv.vatAmount.germanAmount) + durchlaufend \(inv.disbursementTotal.germanAmount) = \(inv.grandTotal.germanAmount) EUR ✓")
    for warning in parsed.warnings { print("⚠️  \(warning)") }

    if dryRun { exit(0) }

    let result = try generator.generate(from: input, parsed: parsed)
    let target = output ?? EInvoiceGenerator.defaultOutputURL(for: input)
    try result.pdf.write(to: target, options: .atomic)
    print("E-Rechnung geschrieben: \(target.path)")
    if let xmlURL {
        try Data(result.xml.utf8).write(to: xmlURL, options: .atomic)
        print("XML geschrieben:        \(xmlURL.path)")
    }
} catch {
    fail("Fehler: \(error.localizedDescription)")
}
