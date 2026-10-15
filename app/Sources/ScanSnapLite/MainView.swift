import AppKit
import PDFKit
import QuickLookThumbnailing
import SwiftUI

extension FormatStyle where Self == Date.FormatStyle {
    /// „22. Sept., 20:32“ – unabhängig von der Systemsprache
    static var germanShort: Date.FormatStyle {
        .dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "de_DE"))
    }
}

/// Das Blau der Scan-Taste am iX500 – einzige Akzentfarbe der App.
extension Color {
    static let scanBlue = Color(red: 0.16, green: 0.47, blue: 1.0)
}

struct MainView: View {
    @EnvironmentObject var scanner: ScannerService

    var body: some View {
        VStack(spacing: 0) {
            HeroView()
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 28)
            Divider()
            RecentScansView()
        }
        .background(.background)
    }
}

// MARK: - Taste + Status

struct HeroView: View {
    @EnvironmentObject var scanner: ScannerService

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            ScanButton()
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity)
                if let detail {
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if let ip = scanner.ip, !isProblem {
                    Text("iX500 über WLAN, \(ip)")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                actions.padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.2), value: headline)
    }

    private var isProblem: Bool {
        switch scanner.state {
        case .offline, .noKey: true
        default: false
        }
    }

    private var headline: String {
        switch scanner.state {
        case .starting, .searching: "Suche Scanner"
        case .ready: scanner.paper == false ? "Papier einlegen" : "Bereit zum Scannen"
        case .scanning: "Scannt"
        case .paused: "Scanner freigegeben"
        case .offline: "Scanner nicht gefunden"
        case .noKey: "Kopplung fehlt"
        }
    }

    private var detail: String? {
        switch scanner.state {
        case .scanning: return scanner.progress
        case .ready:
            if let m = scanner.lastMessage { return m }
            return scanner.paper == true
                ? "Klick auf die Taste oder drück die Scan-Taste am Gerät."
                : "Danach startet der Scan per Klick oder an der Taste am Scanner."
        case .paused: return "Andere Programme können ihn jetzt benutzen."
        case .offline(let m):
            return m.contains("belegt")
                ? "Ein anderes Programm nutzt ihn gerade, z. B. ScanSnap Home."
                : "Ist er eingeschaltet und im selben WLAN?"
        case .noKey: return "Schlüssel und HostID fehlen in ~/.config/scansnap/."
        case .starting, .searching: return "Das dauert ein paar Sekunden."
        }
    }

    @ViewBuilder private var actions: some View {
        switch scanner.state {
        case .offline:
            Button("Erneut suchen") { scanner.retry() }
        case .paused:
            Button("Wieder verbinden") { scanner.togglePause() }
        case .ready:
            Button("Scanner freigeben") { scanner.togglePause() }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
                .help("Trennt die App vom Scanner, z. B. für ScanSnap Home oder die Kommandozeile")
        default:
            EmptyView()
        }
    }
}

/// Runde Taste nach Vorbild der iX500-Scan-Taste: leuchtet blau, wenn gescannt werden kann.
struct ScanButton: View {
    @EnvironmentObject var scanner: ScannerService
    @State private var spin = false
    @State private var pressed = false

    private let size: CGFloat = 116

    private var canScan: Bool { scanner.state.isReady && scanner.paper != false }
    private var scanning: Bool { scanner.state == .scanning }
    private var lit: Bool { canScan || scanning }

    var body: some View {
        Button { if canScan { scanner.scan() } } label: {
            ZStack {
                // Gehäuse-Einfassung
                Circle()
                    .fill(.quaternary)
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
                // Taste
                Circle()
                    .fill(lit ? AnyShapeStyle(Color.scanBlue.gradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
                    .padding(12)
                    .shadow(color: lit ? .scanBlue.opacity(0.55) : .clear, radius: 18)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(lit ? 0.35 : 0.1), lineWidth: 1)
                            .padding(12)
                    )
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(lit ? 1 : 0.6))
                    .contentTransition(.symbolEffect(.replace))
                // Fortschritt beim Scannen
                if scanning {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Color.scanBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(3)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
                        }
                        .onDisappear { spin = false }
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        // nicht .disabled: das würde die leuchtende Taste beim Scannen abblenden
        .allowsHitTesting(canScan)
        .accessibilityAddTraits(canScan ? [] : .isStaticText)
        .keyboardShortcut(.return, modifiers: [])
        .help(canScan ? "Scannen (↩)" : "")
        .accessibilityLabel("Scannen")
        .onLongPressGesture(minimumDuration: 0, pressing: { p in
            withAnimation(.easeOut(duration: 0.1)) { pressed = p && canScan }
        }, perform: {})
        .animation(.easeInOut(duration: 0.3), value: lit)
    }

    private var icon: String {
        switch scanner.state {
        case .scanning: "doc.viewfinder.fill"
        case .offline, .noKey: "wifi.exclamationmark"
        case .paused: "pause.fill"
        case .starting, .searching: "wifi"
        case .ready: scanner.paper == false ? "tray" : "doc.viewfinder"
        }
    }
}

// MARK: - Letzte Scans

struct RecentScansView: View {
    @EnvironmentObject var scanner: ScannerService

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 150), spacing: 18, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Letzte Scans").font(.headline)
                Spacer()
                Button("Im Finder zeigen") { NSWorkspace.shared.open(scanner.settings.outdirURL) }
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            if scanner.recent.isEmpty {
                ContentUnavailableView("Noch keine Scans",
                                       systemImage: "doc.on.doc",
                                       description: Text("Fertige PDFs erscheinen hier und in \(scanner.settings.outdir)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(scanner.recent) { ScanTile(result: $0) }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
    }
}

struct ScanTile: View {
    let result: ScannerService.ScanResult
    @State private var thumb: NSImage?
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let thumb {
                    Image(nsImage: thumb).resizable().scaledToFit()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(hover ? 0.28 : 0.16), radius: hover ? 8 : 3, y: hover ? 4 : 1)

            Text(result.date.formatted(.germanShort))
                .font(.callout)
            Text(result.pages == 1 ? "1 Seite" : "\(result.pages) Seiten")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(result.url) }
        .contextMenu {
            Button("Öffnen") { NSWorkspace.shared.open(result.url) }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([result.url]) }
        }
        .help("\(result.url.lastPathComponent), Doppelklick öffnet das PDF")
        .task(id: result.url) {
            let req = QLThumbnailGenerator.Request(fileAt: result.url, size: CGSize(width: 150, height: 200),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
            thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req).nsImage
        }
    }
}
