import InvoiceKit
import SwiftUI

/// App-Einstellungen (⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var currency = ""
    @State private var buyerID = ""
    @State private var supplierID = ""
    @State private var buyerEmail = ""
    @State private var buyerSMTP = ""
    @State private var message: String?

    var body: some View {
        Form {
            if model.config != nil {
                TextField("Währung (ISO 4217)", text: $currency)
                TextField("Lieferantennummer (BT-29)", text: $supplierID)
                TextField("Käufer-ID (BT-46)", text: $buyerID)
                TextField("Käufer-E-Mail (Kommunikation)", text: $buyerEmail)
                TextField("Käufer-SMTP (BT-49)", text: $buyerSMTP)
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
        supplierID = config.supplierID
        buyerID = config.buyerID
        buyerEmail = config.buyerEmail
        buyerSMTP = config.buyerSMTP
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
            buyerID: buyerID.trimmingCharacters(in: .whitespacesAndNewlines),
            supplierID: supplierID.trimmingCharacters(in: .whitespacesAndNewlines),
            buyerEmail: buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            buyerSMTP: buyerSMTP.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        message = "Gesichert"
    }
}
