import AppKit
import InvoiceKit
import SwiftUI

/// Einstellungen (⌘,): die am häufigsten geänderten Werte direkt bearbeitbar,
/// alles andere in der JSON-Datei.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var hourlyRate = ""
    @State private var terms = ""
    @State private var message: String?

    var body: some View {
        Form {
            if model.config != nil {
                TextField("Stundensatz (€)", text: $hourlyRate)
                TextField("Zahlungsbedingungen", text: $terms, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    if let message { Text(message).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Sichern") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            if let error = model.configError {
                ErrorBox(text: error)
            }
            Section("Alle Angaben (Verkäufer, BMW, Bankverbindung)") {
                Text(AppModel.configURL.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppModel.configURL])
                    }
                    Button("Neu laden") {
                        model.loadConfig()
                        fill()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let config = model.config else { return }
        hourlyRate = config.hourlyRate.germanAmount
        terms = config.payment.terms
        message = nil
    }

    private func save() {
        guard let rate = Decimal(german: hourlyRate), rate > 0 else {
            message = "Ungültiger Stundensatz"
            return
        }
        model.config?.hourlyRate = rate
        model.config?.payment.terms = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveConfig()
        message = model.configError == nil ? "Gesichert" : nil
    }
}
