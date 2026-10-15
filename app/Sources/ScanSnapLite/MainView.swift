import AppKit
import ServiceManagement
import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            ScanTab().tabItem { Label("Scannen", systemImage: "doc.viewfinder") }
            SettingsTab().tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .padding()
    }
}

// MARK: - Scannen

struct ScanTab: View {
    @EnvironmentObject var scanner: ScannerService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusCard()
            HStack {
                Button {
                    scanner.scan()
                } label: {
                    Label("Jetzt scannen", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!scanner.state.isReady || scanner.paper == false)

                Button(scanner.state == .paused ? "Verbinden" : "Freigeben") { scanner.togglePause() }
                    .controlSize(.large)
                    .help("Gibt den Scanner frei, z. B. für ScanSnap Home oder die Kommandozeile")
            }
            if scanner.settings.buttonScan {
                Text("Tipp: Die blaue Scan-Taste am Scanner startet den Scan ebenfalls.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Text("Letzte Scans").font(.headline)
                Spacer()
                Button("Ordner öffnen") { NSWorkspace.shared.open(scanner.settings.outdirURL) }
                    .buttonStyle(.link)
            }
            List(scanner.recent) { r in
                HStack {
                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                    Text(r.url.lastPathComponent)
                    Spacer()
                    Text(r.date, format: .dateTime.day().month().year().hour().minute())
                        .foregroundStyle(.secondary).font(.callout)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { NSWorkspace.shared.open(r.url) }
                .contextMenu {
                    Button("Öffnen") { NSWorkspace.shared.open(r.url) }
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([r.url]) }
                }
            }
            .overlay {
                if scanner.recent.isEmpty {
                    Text("Noch keine Scans").foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

struct StatusCard: View {
    @EnvironmentObject var scanner: ScannerService

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(color)
                .frame(width: 40)
                .symbolEffect(.pulse, isActive: scanner.state == .scanning || scanner.state == .searching)
            VStack(alignment: .leading, spacing: 4) {
                Text(scanner.state.label).font(.title3.weight(.semibold))
                if let ip = scanner.ip {
                    Text("ScanSnap iX500 · \(ip)").foregroundStyle(.secondary)
                }
                if scanner.state.isReady, let paper = scanner.paper {
                    Label(paper ? "Papier eingelegt" : "Einzug leer",
                          systemImage: paper ? "doc.fill" : "tray")
                        .foregroundStyle(paper ? .primary : .secondary)
                }
                if let p = scanner.progress {
                    HStack { ProgressView().controlSize(.small); Text(p) }
                }
                if let m = scanner.lastMessage {
                    Text(m).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var icon: String {
        switch scanner.state {
        case .ready: "checkmark.circle.fill"
        case .scanning: "doc.viewfinder.fill"
        case .searching, .starting: "wifi"
        case .paused: "pause.circle.fill"
        case .offline, .noKey: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch scanner.state {
        case .ready: .green
        case .scanning, .searching, .starting: .blue
        case .paused: .secondary
        case .offline, .noKey: .orange
        }
    }
}

// MARK: - Einstellungen

struct SettingsTab: View {
    @EnvironmentObject var scanner: ScannerService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let langs = [("deu+eng", "Deutsch + Englisch"), ("deu", "Deutsch"), ("eng", "Englisch")]
    private let optimizeLabels = [0: "Aus", 1: "Verlustfrei", 2: "Stark (empfohlen)", 3: "Maximal"]

    var body: some View {
        Form {
            Section("Bild") {
                Picker("Farbmodus", selection: $scanner.settings.mode) {
                    ForEach(ScanSettings.Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Auflösung", selection: $scanner.settings.dpi) {
                    Text("150 dpi").tag(150); Text("200 dpi").tag(200); Text("300 dpi").tag(300)
                }
                .pickerStyle(.segmented)
                LabeledContent("JPEG-Qualität") {
                    HStack {
                        Slider(value: qualityBinding, in: 40...95, step: 5)
                        Text("\(scanner.settings.quality)").monospacedDigit().frame(width: 28)
                    }
                }
                .disabled(scanner.settings.mode == .bw)
                Toggle("Grauen Rand abschneiden", isOn: $scanner.settings.crop)
                Toggle("Leere Seiten entfernen", isOn: $scanner.settings.removeBlank)
                if scanner.settings.removeBlank {
                    LabeledContent("Empfindlichkeit") {
                        Picker("", selection: $scanner.settings.blankThreshold) {
                            Text("Vorsichtig").tag(0.001)
                            Text("Normal").tag(0.003)
                            Text("Streng").tag(0.008)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                }
            }

            Section("PDF") {
                Toggle("Texterkennung (durchsuchbares PDF)", isOn: $scanner.settings.ocr)
                Picker("Sprachen", selection: $scanner.settings.ocrLangs) {
                    ForEach(langs, id: \.0) { Text($0.1).tag($0.0) }
                }
                .disabled(!scanner.settings.ocr)
                Picker("Komprimierung", selection: $scanner.settings.optimize) {
                    ForEach(0...3, id: \.self) { Text(optimizeLabels[$0] ?? "\($0)").tag($0) }
                }
                .disabled(!scanner.settings.ocr)
            }

            Section("Ablage") {
                LabeledContent("Ordner") {
                    HStack {
                        Text(scanner.settings.outdir).lineLimit(1).truncationMode(.middle)
                        Button("Wählen …", action: chooseFolder)
                    }
                }
                TextField("Dateiname", text: $scanner.settings.filename)
                Text("Platzhalter: %Y Jahr, %m Monat, %d Tag, %H%M%S Uhrzeit")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("PDF nach dem Scan öffnen", isOn: $scanner.settings.openAfter)
            }

            Section("Scanner") {
                TextField("IP-Adresse", text: $scanner.settings.scannerIP, prompt: Text("automatisch suchen"))
                Toggle("Scan-Taste am Gerät startet Scan", isOn: $scanner.settings.buttonScan)
                Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            scanner.lastMessage = "Autostart: \(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }

    private var qualityBinding: Binding<Double> {
        Binding(get: { Double(scanner.settings.quality) },
                set: { scanner.settings.quality = Int($0) })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = scanner.settings.outdirURL
        if panel.runModal() == .OK, let url = panel.url {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            scanner.settings.outdir = url.path.hasPrefix(home)
                ? "~" + url.path.dropFirst(home.count) : url.path
        }
    }
}
