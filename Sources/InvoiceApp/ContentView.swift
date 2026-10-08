import InvoiceKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if model.parsed == nil {
                dropZone
            } else {
                InvoiceDetailView()
            }
            Divider()
            footer
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in model.open(url) }
            }
            return true
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Rechnungs-PDF hierher ziehen")
                .font(.title3)
            Button("PDF auswählen …") { model.choosePDF() }
                .controlSize(.large)
            if let error = model.errorMessage ?? model.configError {
                ErrorBox(text: error)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .padding(20)
        )
    }

    private var footer: some View {
        HStack {
            if let url = model.inputURL {
                Label(url.lastPathComponent, systemImage: "doc.richtext")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if model.parsed != nil {
                Button("Andere Rechnung …") { model.choosePDF() }
                Button("E-Rechnung erzeugen …") { model.generate() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}

struct InvoiceDetailView: View {
    @Environment(AppModel.self) private var model

    private static let dateFormat = Date.FormatStyle().day(.twoDigits).month(.twoDigits).year()

    var body: some View {
        @Bindable var model = model
        if let parsed = model.parsed, let config = model.config {
            let inv = parsed.invoice
            Form {
                Section("Rechnung") {
                    LabeledContent("Rechnung Nr.", value: inv.number)
                    LabeledContent("Datum", value: inv.issueDate.formatted(Self.dateFormat))
                    LabeledContent("Leistungszeitraum",
                                   value: "\(inv.billingPeriod.start.formatted(Self.dateFormat)) – \(inv.billingPeriod.end.formatted(Self.dateFormat))")
                    LabeledContent("Unser Zeichen", value: inv.ourReference ?? "–")
                    LabeledContent("Ansprechpartner", value: inv.buyerContactName ?? "–")
                }
                if let buyer = inv.buyer {
                    Section("Käufer") {
                        LabeledContent("Name", value: buyer.name)
                        LabeledContent("Anschrift", value: address(buyer.addressLines + ["\(buyer.postcode) \(buyer.city)"]))
                        LabeledContent("Käufer-ID (BT-46)", value: config.buyerID.isEmpty ? "–" : config.buyerID)
                        if let vatId = buyer.vatId {
                            LabeledContent("USt-ID", value: vatId)
                        }
                    }
                }
                if let seller = inv.seller {
                    Section("Verkäufer") {
                        LabeledContent("Name", value: seller.name)
                        LabeledContent("Anschrift", value: address([seller.street, "\(seller.postcode) \(seller.city)"]))
                        LabeledContent("Lieferantennummer (BT-29)", value: config.supplierID.isEmpty ? (seller.id ?? "–") : config.supplierID)
                        if let contactName = seller.contactName {
                            LabeledContent("Ansprechpartner", value: contactName)
                        }
                        if let phone = seller.phone {
                            LabeledContent("Telefon", value: phone)
                        }
                        if let email = seller.email {
                            LabeledContent("E-Mail", value: email)
                        }
                        if let vatId = seller.vatId {
                            LabeledContent("USt-ID", value: vatId)
                        }
                    }
                }
                Section("Kundenvorgaben") {
                    TextField("Aktenzeichen des Kunden", text: Binding(
                        get: { model.parsed?.invoice.fileReference ?? "" },
                        set: { model.parsed?.invoice.fileReference = $0; model.savedURL = nil }
                    ))
                    LabeledContent("Bemerkung (BT-22)", value: config.referenceNotePrefix + inv.fileReference)
                }
                Section("Positionen") {
                    ForEach(inv.lines) { line in
                        LineRow(line: line, vatRate: inv.vatRate)
                    }
                }
                Section("Summen") {
                    LabeledContent("Netto (USt-pflichtig)", value: euro(inv.taxableTotal))
                    LabeledContent("Umsatzsteuer \(inv.vatRate.xmlQuantity) %", value: euro(inv.vatAmount))
                    if !inv.disbursementLines.isEmpty {
                        LabeledContent("Durchlaufende Posten", value: euro(inv.disbursementTotal))
                    }
                    LabeledContent("Endbetrag") {
                        Text(euro(inv.grandTotal)).bold()
                    }
                    Label("Stimmt mit den Beträgen im PDF überein", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                if !parsed.warnings.isEmpty || model.errorMessage != nil || model.savedURL != nil {
                    Section {
                        ForEach(parsed.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if let error = model.errorMessage {
                            ErrorBox(text: error)
                        }
                        if let saved = model.savedURL {
                            HStack {
                                Label("Gespeichert: \(saved.lastPathComponent)", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                                Button("Im Finder zeigen") { model.revealSaved() }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func euro(_ value: Decimal) -> String {
        value.germanAmount + " €"
    }

    private func address(_ lines: [String]) -> String {
        lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct LineRow: View {
    let line: InvoiceLine
    let vatRate: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.name).fontWeight(.medium)
                Spacer()
                Text(line.amount.germanAmount + " €").monospacedDigit()
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if line.description != line.name {
                Text(line.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        let qty = line.unit == .hour
            ? "\(line.quantity.xmlQuantity.replacingOccurrences(of: ".", with: ",")) Std. à \(line.unitPrice.germanAmount) €"
            : "pauschal"
        let tax = line.kind == .service ? "USt \(vatRate.xmlQuantity) %" : "durchlaufender Posten, ohne USt"
        return "\(qty) · \(tax)"
    }
}

struct ErrorBox: View {
    let text: String

    var body: some View {
        Label {
            Text(text).textSelection(.enabled)
        } icon: {
            Image(systemName: "xmark.octagon.fill")
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
