import AppKit
import Foundation
import InvoiceKit
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var config: InvoiceConfig?
    var configError: String?

    var inputURL: URL?
    var parsed: ParseResult?
    var errorMessage: String?
    var savedURL: URL?

    /// Ablage der Konfiguration: ~/Library/Application Support/E-Invoice Generator/config.json
    static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("E-Invoice Generator", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }

    init() {
        UserDefaults.standard.removeObject(forKey: "preferences.hourlyRate")
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
            var loadedConfig = try InvoiceConfig.load(from: url)
            if let currency = UserDefaults.standard.string(forKey: "preferences.currency") {
                loadedConfig.currency = currency
            }
            if let buyerID = UserDefaults.standard.string(forKey: "preferences.buyerID") {
                loadedConfig.buyerID = buyerID
            }
            config = loadedConfig
            configError = nil
        } catch {
            config = nil
            configError = "Konfiguration konnte nicht geladen werden (\(url.path)): \(error.localizedDescription)"
        }
        if let inputURL { open(inputURL) }
    }

    func savePreferences(currency: String, buyerID: String) {
        guard var updatedConfig = config else { return }
        updatedConfig.currency = currency
        updatedConfig.buyerID = buyerID
        config = updatedConfig
        UserDefaults.standard.set(currency, forKey: "preferences.currency")
        UserDefaults.standard.set(buyerID, forKey: "preferences.buyerID")
        configError = nil
        if let inputURL { open(inputURL) }
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
