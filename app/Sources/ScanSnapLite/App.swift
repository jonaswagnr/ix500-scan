import AppKit
import SwiftUI

@main
struct ScanSnapLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var scanner = ScannerService()

    var body: some Scene {
        Window("ScanSnap Lite", id: "main") {
            MainView()
                .environmentObject(scanner)
                .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 640)
                .tint(.scanBlue)
                .onAppear { delegate.scanner = scanner }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 620, height: 640)

        Settings {
            SettingsView().environmentObject(scanner)
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(scanner)
        } label: {
            Image(systemName: scanner.state == .scanning ? "doc.viewfinder.fill" : "doc.viewfinder")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var scanner: ScannerService?

    // Fenster schließen beendet die App nicht, sie bleibt in der Menüleiste
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { scanner?.stop() }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var scanner: ScannerService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        if let p = scanner.progress { Text(p) }
        Divider()
        Button("Scannen") { scanner.scan() }
            .keyboardShortcut("s")
            .disabled(!scanner.state.isReady || scanner.paper == false)
        if case .offline = scanner.state {
            Button("Erneut suchen") { scanner.retry() }
        }
        Button(scanner.state == .paused ? "Wieder verbinden" : "Scanner freigeben") {
            scanner.togglePause()
        }
        if !scanner.recent.isEmpty {
            Divider()
            Text("Letzte Scans")
            ForEach(scanner.recent.prefix(5)) { r in
                Button(r.date.formatted(.germanShort)) {
                    NSWorkspace.shared.open(r.url)
                }
            }
            Button("Im Finder zeigen") { NSWorkspace.shared.open(scanner.settings.outdirURL) }
        }
        Divider()
        Button("ScanSnap Lite öffnen") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")
        SettingsLink { Text("Einstellungen …") }
            .keyboardShortcut(",")
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch scanner.state {
        case .ready: scanner.paper == false ? "Bereit, Einzug leer" : "Bereit, Papier liegt ein"
        case .offline: "Scanner nicht gefunden"
        default: scanner.state.label
        }
    }
}
