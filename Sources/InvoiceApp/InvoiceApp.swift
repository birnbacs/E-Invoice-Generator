import AppKit
import SwiftUI

@main
struct InvoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("E-Invoice Generator", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Rechnung öffnen …") { model.choosePDF() }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Nötig, damit die App ohne Xcode-Projekt (per `swift run`) als normale App mit Fenster startet.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppModel.shared.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
