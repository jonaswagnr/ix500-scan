import AppKit
import ServiceManagement
import SwiftUI

/// Mac-typisches Einstellungsfenster (⌘,) mit vier Bereichen.
struct SettingsView: View {
    var body: some View {
        TabView {
            ImageSettings().tabItem { Label("Bild", systemImage: "photo") }
            PDFSettings().tabItem { Label("PDF", systemImage: "doc.richtext") }
            StorageSettings().tabItem { Label("Ablage", systemImage: "folder") }
            ScannerSettings().tabItem { Label("Scanner", systemImage: "scanner") }
        }
        .frame(width: 500)
        .tint(.scanBlue)
    }
}

private struct ImageSettings: View {
    @EnvironmentObject var scanner: ScannerService

    var body: some View {
        Form {
            Picker("Farbmodus", selection: $scanner.settings.mode) {
                ForEach(ScanSettings.Mode.allCases) { Text($0.label).tag($0) }
            }
            Picker("Auflösung", selection: $scanner.settings.dpi) {
                Text("150 dpi, kleinste Dateien").tag(150)
                Text("200 dpi").tag(200)
                Text("300 dpi, beste Qualität").tag(300)
            }
            LabeledContent("Qualität") {
                HStack {
                    Slider(value: Binding(get: { Double(scanner.settings.quality) },
                                          set: { scanner.settings.quality = Int($0) }),
                           in: 40...95, step: 5) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("klein").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("scharf").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(scanner.settings.mode == .bw)

            Section {
                Toggle("Rand um das Blatt abschneiden", isOn: $scanner.settings.crop)
                Toggle("Leere Seiten entfernen", isOn: $scanner.settings.removeBlank)
                Picker("Als leer gilt eine Seite", selection: $scanner.settings.blankThreshold) {
                    Text("fast ohne Spuren").tag(0.001)
                    Text("mit wenigen Spuren").tag(0.003)
                    Text("mit etwas Durchschein").tag(0.008)
                }
                .disabled(!scanner.settings.removeBlank)
            } footer: {
                Text("Per WLAN scannt der iX500 immer in Farbe mit 300 dpi. Modus und Auflösung werden danach umgerechnet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PDFSettings: View {
    @EnvironmentObject var scanner: ScannerService

    var body: some View {
        Form {
            Toggle("Text erkennen, damit das PDF durchsuchbar ist", isOn: $scanner.settings.ocr)
            Picker("Sprachen", selection: $scanner.settings.ocrLangs) {
                Text("Deutsch und Englisch").tag("deu+eng")
                Text("Deutsch").tag("deu")
                Text("Englisch").tag("eng")
            }
            .disabled(!scanner.settings.ocr)
            Picker("Komprimierung", selection: $scanner.settings.optimize) {
                Text("Aus").tag(0)
                Text("Verlustfrei").tag(1)
                Text("Stark").tag(2)
                Text("Maximal").tag(3)
            }
            .disabled(!scanner.settings.ocr)
        }
        .formStyle(.grouped)
    }
}

private struct StorageSettings: View {
    @EnvironmentObject var scanner: ScannerService

    var body: some View {
        Form {
            LabeledContent("Ordner") {
                HStack {
                    Text(scanner.settings.outdir).lineLimit(1).truncationMode(.middle)
                    Button("Ändern …", action: chooseFolder)
                }
            }
            Section {
                TextField("Dateiname", text: $scanner.settings.filename)
            } footer: {
                Text("%Y Jahr, %m Monat, %d Tag, %H %M %S Uhrzeit. Beispiel: \(example)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("PDF nach dem Scan öffnen", isOn: $scanner.settings.openAfter)
        }
        .formStyle(.grouped)
    }

    private var example: String {
        var tm = tm()
        var t = time(nil)
        localtime_r(&t, &tm)
        var buf = [Int8](repeating: 0, count: 128)
        let n = strftime(&buf, buf.count, scanner.settings.filename, &tm)
        return n > 0 ? String(cString: buf) + ".pdf" : "—"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = scanner.settings.outdirURL
        if panel.runModal() == .OK, let url = panel.url {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            scanner.settings.outdir = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
        }
    }
}

private struct ScannerSettings: View {
    @EnvironmentObject var scanner: ScannerService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                TextField("IP-Adresse", text: $scanner.settings.scannerIP, prompt: Text("automatisch suchen"))
            } footer: {
                Text("Leer lassen, dann sucht die App den Scanner im WLAN. Eine feste IP im Router macht die Verbindung schneller.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("Scan-Taste am Scanner startet den Scan", isOn: $scanner.settings.buttonScan)
            Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        scanner.lastMessage = "Autostart: \(error.localizedDescription)"
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .formStyle(.grouped)
    }
}
