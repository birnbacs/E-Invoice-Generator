import InvoiceKit
import SwiftUI

/// App-Einstellungen (⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var currency = ""
    @State private var buyerID = ""
    @State private var message: String?

    var body: some View {
        Form {
            if model.config != nil {
                TextField("Währung (ISO 4217)", text: $currency)
                TextField("Käufer-ID (BT-46)", text: $buyerID)
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
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let config = model.config else { return }
        currency = config.currency
        buyerID = config.buyerID
        message = nil
    }

    private func save() {
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil else {
            message = "Bitte einen ISO-4217-Währungscode mit drei Buchstaben eingeben."
            return
        }
        model.savePreferences(
            currency: normalizedCurrency,
            buyerID: buyerID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        message = "Gesichert"
    }
}
