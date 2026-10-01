import AppKit
import Foundation
import InvoiceKit
import Observation

@MainActor
@Observable
final class AppModel {
    var config: InvoiceConfig?
    var configError: String?

    var inputURL: URL?
    var parsed: ParseResult?
    var errorMessage: String?
    var savedURL: URL?

    /// Ablage der Konfiguration: ~/Library/Application Support/BMW-E-Invoice/config.json
    static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BMW-E-Invoice", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }

    init() {
        loadConfig()
    }

    func loadConfig() {
        let url = Self.configURL
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                // Beim ersten Start die mitgelieferte Vorlage kopieren.
                guard let bundled = Bundle.main.url(forResource: "config", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
                }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundled, to: url)
            }
            config = try InvoiceConfig.load(from: url)
            configError = nil
        } catch {
            config = nil
            configError = "Konfiguration konnte nicht geladen werden (\(url.path)): \(error.localizedDescription)"
        }
        if let inputURL { open(inputURL) }
    }

    func saveConfig() {
        guard let config else { return }
        do {
            try config.save(to: Self.configURL)
            if let inputURL { open(inputURL) }
        } catch {
            configError = "Konfiguration konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func open(_ url: URL) {
        inputURL = url
        parsed = nil
        errorMessage = nil
        savedURL = nil
        guard let config else {
            errorMessage = configError
            return
        }
        do {
            parsed = try InvoiceParser(config: config).parse(pdfAt: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func generate() {
        guard let config, let inputURL, var parsed else { return }
        parsed.invoice.fileReference = parsed.invoice.fileReference.trimmingCharacters(in: .whitespaces)
        guard !parsed.invoice.fileReference.isEmpty else {
            errorMessage = "Bitte ein Aktenzeichen angeben."
            return
        }
        let proposed = EInvoiceGenerator.defaultOutputURL(for: inputURL)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = proposed.deletingLastPathComponent()
        panel.nameFieldStringValue = proposed.lastPathComponent
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            let result = try EInvoiceGenerator(config: config).generate(from: inputURL, parsed: parsed)
            try result.pdf.write(to: target, options: .atomic)
            savedURL = target
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealSaved() {
        if let savedURL { NSWorkspace.shared.activateFileViewerSelecting([savedURL]) }
    }
}
