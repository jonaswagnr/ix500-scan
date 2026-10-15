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
                .frame(minWidth: 620, minHeight: 560)
                .onAppear { delegate.scanner = scanner }
        }
        .windowResizability(.contentMinSize)

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
        Button("Jetzt scannen") { scanner.scan() }
            .keyboardShortcut("s")
            .disabled(!scanner.state.isReady || scanner.paper == false)
        Button(scanner.state == .paused ? "Scanner wieder verbinden" : "Scanner freigeben (Pause)") {
            scanner.togglePause()
        }
        if !scanner.recent.isEmpty {
            Divider()
            Text("Letzte Scans")
            ForEach(scanner.recent.prefix(5)) { r in
                Button(r.url.lastPathComponent) { NSWorkspace.shared.open(r.url) }
            }
            Button("Ablageordner öffnen") { NSWorkspace.shared.open(scanner.settings.outdirURL) }
        }
        Divider()
        Button("Fenster öffnen …") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        var s = scanner.state.label
        if scanner.state.isReady, let paper = scanner.paper {
            s += paper ? " · Papier eingelegt" : " · Einzug leer"
        }
        return s
    }
}
