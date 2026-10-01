import Foundation

/// Bettet das ZUGFeRD-XML in ein bestehendes PDF/A-3 ein.
///
/// Das Original-PDF wird nicht verändert. An die Datei wird ein
/// "inkrementelles Update" angehängt (PDF-Standard, Abschnitt 7.5.6), das
///  - das XML als eingebettete Datei (`/AFRelationship /Alternative`) enthält,
///  - den Dokumentkatalog um `/Names` und `/AF` ergänzt und
///  - die XMP-Metadaten um die ZUGFeRD-Angaben erweitert.
///
/// Unterstützt werden PDFs mit klassischer xref-Tabelle und unkomprimiertem
/// Katalog, wie LibreOffice sie beim PDF/A-Export erzeugt.
public struct ZUGFeRDEmbedder {
    public enum Error: LocalizedError, Equatable {
        case structure(String)
        case unsupported(String)
        case alreadyEInvoice

        public var errorDescription: String? {
            switch self {
            case .structure(let detail): return "Das PDF hat einen unerwarteten Aufbau: \(detail)"
            case .unsupported(let detail): return "Dieses PDF wird nicht unterstützt: \(detail)"
            case .alreadyEInvoice: return "Das PDF enthält bereits eine E-Rechnung bzw. eingebettete Dateien."
            }
        }
    }

    /// ZUGFeRD 2.1 / Factur-X 1.0
    public static let xmpNamespace = "urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#"
    public static let conformanceLevel = "EN 16931"

    public init() {}

    public func embed(xml: Data, into pdf: Data, modificationDate: Date = Date()) throws -> Data {
        var reader = PDFReader(data: pdf)
        let trailer = try reader.trailer()
        guard let root = trailer.reference("Root") else { throw Error.structure("kein /Root im Trailer") }
        guard let size = trailer.integer("Size") else { throw Error.structure("kein /Size im Trailer") }

        let catalog = try reader.dictionaryText(ofObject: root)
        if catalog.contains("/Names") || catalog.contains("/AF") {
            throw Error.alreadyEInvoice
        }
        guard let metadataRef = PDFReader.reference(named: "Metadata", in: catalog) else {
            throw Error.unsupported("keine XMP-Metadaten (kein PDF/A?)")
        }
        let xmp = try reader.streamContent(ofObject: metadataRef)
        guard let xmpText = String(data: xmp, encoding: .utf8) else {
            throw Error.unsupported("XMP-Metadaten sind nicht UTF-8")
        }
        if xmpText.contains("pdfaid:part>3") == false && xmpText.contains("pdfaid:part=\"3\"") == false {
            throw Error.unsupported("das PDF ist kein PDF/A-3")
        }
        if xmpText.contains("factur-x") || xmpText.contains("zugferd") {
            throw Error.alreadyEInvoice
        }

        let fileObj = size
        let specObj = size + 1
        let metaObj = size + 2
        let pdfDate = Self.pdfDate(modificationDate)

        var update = IncrementalUpdate(base: pdf)

        update.object(fileObj, dictionary: "<</Type/EmbeddedFile/Subtype/text#2Fxml/Params<</ModDate(\(pdfDate))/Size \(xml.count)>>/Length \(xml.count)>>", stream: xml)

        update.object(specObj, dictionary: "<</Type/Filespec/F(\(CIIWriter.fileName))/UF(\(CIIWriter.fileName))/Desc(Factur-X/ZUGFeRD Rechnung)/AFRelationship/Alternative/EF<</F \(fileObj) 0 R/UF \(fileObj) 0 R>>>>")

        let newXMP = Data(try Self.extendXMP(xmpText).utf8)
        update.object(metaObj, dictionary: "<</Type/Metadata/Subtype/XML/Length \(newXMP.count)>>", stream: newXMP)

        var newCatalog = catalog.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newCatalog.hasSuffix(">>") else { throw Error.structure("Katalog ist kein Dictionary") }
        newCatalog.removeLast(2)
        newCatalog = newCatalog.replacingOccurrences(of: "/Metadata \(metadataRef) 0 R", with: "/Metadata \(metaObj) 0 R")
        newCatalog += "\n/Names<</EmbeddedFiles<</Names[(\(CIIWriter.fileName)) \(specObj) 0 R]>>>>"
        newCatalog += "\n/AF[\(specObj) 0 R]>>"
        update.object(root, dictionary: newCatalog)

        var newTrailer = "/Size \(size + 3)/Root \(root) 0 R"
        if let info = trailer.reference("Info") { newTrailer += "/Info \(info) 0 R" }
        if let id = trailer.raw("ID") { newTrailer += "/ID \(id)" }
        return update.finish(trailer: newTrailer, previousXRef: reader.startXRef)
    }

    /// Ergänzt die XMP-Metadaten um das Factur-X-Erweiterungsschema und die fx-Angaben.
    static func extendXMP(_ xmp: String) throws -> String {
        guard let range = xmp.range(of: "</rdf:RDF>") else {
            throw Error.structure("XMP ohne rdf:RDF")
        }
        let addition = """
          <rdf:Description rdf:about="" xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/" xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#" xmlns:pdfaProperty="http://www.aiim.org/pdfa/ns/property#">
           <pdfaExtension:schemas>
            <rdf:Bag>
             <rdf:li rdf:parseType="Resource">
              <pdfaSchema:schema>Factur-X PDFA Extension Schema</pdfaSchema:schema>
              <pdfaSchema:namespaceURI>\(xmpNamespace)</pdfaSchema:namespaceURI>
              <pdfaSchema:prefix>fx</pdfaSchema:prefix>
              <pdfaSchema:property>
               <rdf:Seq>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>DocumentFileName</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>name of the embedded XML invoice file</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>DocumentType</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>INVOICE</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>Version</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>The actual version of the Factur-X XML schema</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>ConformanceLevel</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>The conformance level of the embedded Factur-X data</pdfaProperty:description>
                </rdf:li>
               </rdf:Seq>
              </pdfaSchema:property>
             </rdf:li>
            </rdf:Bag>
           </pdfaExtension:schemas>
          </rdf:Description>
          <rdf:Description rdf:about="" xmlns:fx="\(xmpNamespace)">
           <fx:DocumentType>INVOICE</fx:DocumentType>
           <fx:DocumentFileName>\(CIIWriter.fileName)</fx:DocumentFileName>
           <fx:Version>1.0</fx:Version>
           <fx:ConformanceLevel>\(conformanceLevel)</fx:ConformanceLevel>
          </rdf:Description>

        """
        var result = xmp
        result.insert(contentsOf: addition, at: range.lowerBound)
        return result
    }

    /// PDF-Datumsformat, z. B. D:20261001101500+02'00'
    static func pdfDate(_ date: Date) -> String {
        let tz = TimeZone(identifier: "Europe/Berlin")!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyyMMddHHmmss"
        let offset = tz.secondsFromGMT(for: date) / 60
        let sign = offset >= 0 ? "+" : "-"
        return String(format: "D:%@%@%02d'%02d'", f.string(from: date), sign, abs(offset) / 60, abs(offset) % 60)
    }
}

// MARK: - Lesen der PDF-Struktur

/// Liest gerade so viel PDF-Struktur, wie für das Update nötig ist.
/// Texte werden als ISO-Latin-1 gelesen, damit Bytes und Zeichen 1:1 übereinstimmen.
struct PDFReader {
    let data: Data
    private(set) var startXRef = 0
    private var offsets: [Int: Int] = [:]

    init(data: Data) {
        self.data = data
    }

    struct Trailer {
        let text: String

        func reference(_ key: String) -> Int? { PDFReader.reference(named: key, in: text) }

        func integer(_ key: String) -> Int? {
            guard let m = text.firstMatch(of: try! Regex("/\(key)\\s+(\\d+)(?!\\s+\\d+\\s+R)")),
                  let s = m.output[1].substring else { return nil }
            return Int(s)
        }

        /// Roher Wert, z. B. für /ID [<…><…>]
        func raw(_ key: String) -> String? {
            guard let m = text.firstMatch(of: try! Regex("/\(key)\\s*(\\[[^\\]]*\\])")),
                  let s = m.output[1].substring else { return nil }
            return String(s)
        }
    }

    static func reference(named key: String, in text: String) -> Int? {
        guard let m = text.firstMatch(of: try! Regex("/\(key)\\s+(\\d+)\\s+0\\s+R")),
              let s = m.output[1].substring else { return nil }
        return Int(s)
    }

    private func text(_ range: Range<Int>) -> String {
        String(data: data.subdata(in: range), encoding: .isoLatin1) ?? ""
    }

    /// Liest startxref, die xref-Tabelle(n) und den neuesten Trailer.
    mutating func trailer() throws -> Trailer {
        let tailStart = max(0, data.count - 2048)
        let tail = text(tailStart..<data.count)
        guard let r = tail.range(of: "startxref", options: .backwards),
              let m = tail[r.upperBound...].firstMatch(of: /\s*(\d+)/),
              let offset = Int(m.1)
        else { throw ZUGFeRDEmbedder.Error.structure("startxref nicht gefunden") }
        startXRef = offset

        var newest: Trailer?
        var next: Int? = offset
        var visited = Set<Int>()
        while let position = next, !visited.contains(position) {
            visited.insert(position)
            let section = try readXRefSection(at: position)
            if newest == nil { newest = section }
            next = section.integer("Prev")
        }
        guard let newest else { throw ZUGFeRDEmbedder.Error.structure("kein Trailer") }
        return newest
    }

    private mutating func readXRefSection(at position: Int) throws -> Trailer {
        guard position < data.count else { throw ZUGFeRDEmbedder.Error.structure("startxref zeigt ins Leere") }
        let chunk = text(position..<data.count)
        guard chunk.hasPrefix("xref") else {
            throw ZUGFeRDEmbedder.Error.unsupported("komprimierte Querverweise (xref-Stream)")
        }
        guard let trailerRange = chunk.range(of: "trailer") else {
            throw ZUGFeRDEmbedder.Error.structure("trailer fehlt")
        }
        let table = chunk[chunk.index(chunk.startIndex, offsetBy: 4)..<trailerRange.lowerBound]
        var lines = table.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }[...]
        while let header = lines.popFirst(), !header.isEmpty {
            let parts = header.split(separator: " ")
            guard parts.count == 2, let first = Int(parts[0]), let count = Int(parts[1]) else {
                throw ZUGFeRDEmbedder.Error.structure("xref-Tabelle: \(header)")
            }
            for i in 0..<count {
                guard let entry = lines.popFirst() else { throw ZUGFeRDEmbedder.Error.structure("xref-Tabelle zu kurz") }
                let fields = entry.split(separator: " ")
                // Neuere Abschnitte haben Vorrang: nur setzen, wenn noch unbekannt.
                if fields.count == 3, fields[2] == "n", let off = Int(fields[0]), offsets[first + i] == nil {
                    offsets[first + i] = off
                }
            }
        }
        let afterTrailer = chunk[trailerRange.upperBound...]
        let end = afterTrailer.range(of: "startxref")?.lowerBound ?? afterTrailer.endIndex
        return Trailer(text: String(afterTrailer[..<end]))
    }

    /// Text zwischen "n 0 obj" und "endobj" bzw. "stream".
    private func objectBody(_ number: Int) throws -> (text: String, start: Int) {
        guard let offset = offsets[number] else { throw ZUGFeRDEmbedder.Error.structure("Objekt \(number) nicht in xref") }
        let chunk = text(offset..<min(data.count, offset + 64 * 1024))
        guard let header = chunk.firstMatch(of: try! Regex("^\\s*\(number)\\s+0\\s+obj")) else {
            throw ZUGFeRDEmbedder.Error.structure("Objekt \(number) nicht an erwarteter Stelle")
        }
        let rest = chunk[header.range.upperBound...]
        let end = [rest.range(of: "endobj")?.lowerBound, rest.range(of: "stream")?.lowerBound]
            .compactMap { $0 }.min() ?? rest.endIndex
        // Latin-1: ein Unicode-Skalar je Byte (Character würde CRLF zusammenfassen).
        let bodyStart = offset + chunk.unicodeScalars.distance(from: chunk.startIndex, to: header.range.upperBound)
        return (String(rest[..<end]), bodyStart)
    }

    func dictionaryText(ofObject number: Int) throws -> String {
        try objectBody(number).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inhalt eines unkomprimierten Streams.
    func streamContent(ofObject number: Int) throws -> Data {
        let (dict, bodyStart) = try objectBody(number)
        if dict.contains("/Filter") { throw ZUGFeRDEmbedder.Error.unsupported("komprimierte XMP-Metadaten") }
        guard let m = dict.firstMatch(of: /\/Length\s+(\d+)(?!\s+\d+\s+R)/), let length = Int(m.1) else {
            throw ZUGFeRDEmbedder.Error.unsupported("Stream-Länge ist indirekt angegeben")
        }
        var position = bodyStart + dict.unicodeScalars.count + "stream".unicodeScalars.count
        // Nach "stream" folgt CRLF oder LF.
        if data[position] == 0x0D { position += 1 }
        if data[position] == 0x0A { position += 1 }
        guard position + length <= data.count else { throw ZUGFeRDEmbedder.Error.structure("Stream zu lang") }
        return data.subdata(in: position..<(position + length))
    }
}

// MARK: - Schreiben des Updates

struct IncrementalUpdate {
    private(set) var output: Data
    private var offsets: [(Int, Int)] = []

    init(base: Data) {
        output = base
        if output.last != 0x0A { output.append(0x0A) }
    }

    private mutating func append(_ text: String) {
        output.append(text.data(using: .isoLatin1)!)
    }

    mutating func object(_ number: Int, dictionary: String, stream: Data? = nil) {
        offsets.append((number, output.count))
        append("\(number) 0 obj\n\(dictionary)\n")
        if let stream {
            append("stream\n")
            output.append(stream)
            append("\nendstream\n")
        }
        append("endobj\n")
    }

    mutating func finish(trailer: String, previousXRef: Int) -> Data {
        let xrefOffset = output.count
        append("xref\n")
        // Zusammenhängende Objektnummern zu Unterabschnitten bündeln.
        let sorted = offsets.sorted { $0.0 < $1.0 }
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count, sorted[j + 1].0 == sorted[j].0 + 1 { j += 1 }
            append("\(sorted[i].0) \(j - i + 1)\n")
            for k in i...j {
                append(String(format: "%010d 00000 n\r\n", sorted[k].1))
            }
            i = j + 1
        }
        append("trailer\n<<\(trailer)/Prev \(previousXRef)>>\nstartxref\n\(xrefOffset)\n%%EOF\n")
        return output
    }
}
