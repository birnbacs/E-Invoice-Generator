# E-Invoice Generator

Erzeugt aus einer mit LibreOffice exportierten Rechnung (PDF/A-3) eine
ZUGFeRD-2.1-E-Rechnung (Profil EN 16931). Das XML wird per inkrementellem
Update angehängt; das Original-PDF bleibt Byte für Byte erhalten.

## Benutzung

- App bauen: `scripts/build-app.sh` → `build/E-Invoice Generator.app`
- Kommandozeile: `swift run invoice-cli Referenzen/BMW3090-re.pdf [--xml out.xml] [--dry-run]`
- Tests: `swift test`
- Prüfen mit Mustang (nur Entwicklung): `scripts/setup-tools.sh`, dann `scripts/validate.sh datei.pdf`

## Konfiguration

Währung und Käufer-ID lassen sich in den Einstellungen (⌘,) verwalten.
Verkäufer-, Käufer- und Zahlungsdaten werden beim Import aus dem Rechnungs-PDF
gelesen. `Config/config.json` liefert die initialen Standardwerte für Währung
Käufer-ID (`A1`) und Stundensatz sowie den BT-22-Präfix und die Begründung für
durchlaufende Posten; geänderte Preferences für Währung und Käufer-ID speichert
die App separat.

## Abbildung PDF → XML

| PDF                                   | XML                                         |
|---------------------------------------|---------------------------------------------|
| Rechnung Nr.                          | BT-1                                        |
| „München, den …“                      | BT-2                                        |
| Ihr Zeichen                           | BT-22 `REF. <Aktenzeichen>`                 |
| Leistungszeitraum                     | BG-14 (ganze Monate), BT-72 = Monatsende    |
| Patentreferent …                      | BT-56 Ansprechpartner Käufer                |
| Positionen vor „Zwischensumme“        | Rechnungspositionen, USt-Kategorie S        |
| Positionen nach „Umsatzsteuer“        | durchlaufende Posten, USt-Kategorie E       |
| „x abrechenbare Stunden à y €“        | Menge x, Einheit HUR, Preis y               |
| fest: `A1`                            | BT-46 BuyerTradeParty/ID                    |
| fest: `125593-10`                     | BT-29 SellerTradeParty/ID                   |

Stimmen Zwischensumme, Umsatzsteuer oder Endbetrag nicht mit den Positionen
überein, wird keine E-Rechnung erzeugt.
