import AppKit
import Foundation
import PDFKit
import UserNotifications

/// Startet scansnapd.py, liest dessen JSON-Ereignisse und schickt Befehle.
@MainActor
final class ScannerService: ObservableObject {
    enum State: Equatable {
        case starting, searching, ready, scanning, paused
        case offline(String), noKey(String)

        var label: String {
            switch self {
            case .starting: "Starte …"
            case .searching: "Suche Scanner …"
            case .ready: "Bereit"
            case .scanning: "Scannt …"
            case .paused: "Pausiert"
            case .offline(let m): m
            case .noKey(let m): m
            }
        }
        var isReady: Bool { self == .ready }
    }

    struct ScanResult: Identifiable, Hashable {
        let url: URL
        let date: Date
        let pages: Int
        var id: URL { url }
    }

    @Published var state: State = .starting
    @Published var ip: String?
    @Published var paper: Bool?
    @Published var progress: String?
    @Published var lastMessage: String?
    @Published var recent: [ScanResult] = []
    @Published var settings = ScanSettings.load() {
        didSet { if settings != oldValue { settings.save(); refreshRecent() } }
    }

    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()

    /// Demo-Modus für Screenshots: SCANSNAP_DEMO=ready|scanning, SCANSNAP_DEMO_DIR=<Ordner mit PDFs>
    private let demo = ProcessInfo.processInfo.environment["SCANSNAP_DEMO"]

    init() {
        if let demo {
            ip = "192.168.1.50"
            paper = true
            state = demo == "scanning" ? .scanning : .ready
            progress = demo == "scanning" ? "Seite 3 empfangen" : nil
            refreshRecent()
            return
        }
        settings.save()  // Datei mit allen Schlüsseln anlegen, damit der Dienst sie findet
        refreshRecent()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        start()
    }

    // MARK: Prozess

    private func start() {
        guard let scripts = Bundle.main.resourceURL?.appendingPathComponent("python"),
              FileManager.default.fileExists(atPath: scripts.appendingPathComponent("scansnapd.py").path) else {
            state = .offline("Python-Dateien fehlen im App-Bundle")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-u", scripts.appendingPathComponent("scansnapd.py").path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        let out = Pipe(), inp = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            Task { @MainActor in self?.consume(data) }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            if let s = String(data: h.availableData, encoding: .utf8), !s.isEmpty {
                FileHandle.standardError.write(Data(("[scansnapd] " + s).utf8))
            }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self, self.process === proc else { return }
                self.state = .offline("Dienst beendet – starte neu …")
                try? await Task.sleep(for: .seconds(3))
                self.start()
            }
        }
        do {
            try p.run()
            process = p
            stdin = inp.fileHandleForWriting
        } catch {
            state = .offline("Dienst konnte nicht starten: \(error.localizedDescription)")
        }
    }

    func stop() {
        send(["cmd": "quit"])
        let p = process
        process = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p?.isRunning == true { p?.terminate() } }
    }

    private func send(_ cmd: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: cmd) else { return }
        stdin?.write(data + Data("\n".utf8))
    }

    // MARK: Befehle

    func scan() { send(["cmd": "scan"]) }

    /// Nach einem Fehler sofort neu suchen statt auf den nächsten Versuch zu warten.
    func retry() {
        state = .searching
        send(["cmd": "resume"])
    }

    func togglePause() {
        if state == .paused { send(["cmd": "resume"]); state = .starting }
        else { send(["cmd": "pause"]) }
    }

    // MARK: Ereignisse

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                handle(obj)
            }
        }
    }

    private func handle(_ e: [String: Any]) {
        switch e["event"] as? String {
        case "status":
            ip = e["ip"] as? String
            paper = e["paper"] as? Bool
            let msg = e["message"] as? String ?? ""
            switch e["state"] as? String {
            case "searching": state = .searching
            case "ready": state = .ready
            case "scanning": state = .scanning
            case "paused": state = .paused
            case "nokey": state = .noKey(msg)
            default: state = .offline(msg.isEmpty ? "Nicht verbunden" : msg)
            }
        case "button":
            lastMessage = "Scan-Taste gedrückt"
        case "scan_started":
            state = .scanning
            progress = "Scan läuft …"
        case "page":
            progress = "Seite \(e["n"] as? Int ?? 0) empfangen"
        case "processing":
            progress = (e["step"] as? String) == "ocr" ? "Texterkennung …" : "Bilder aufbereiten …"
        case "done":
            progress = nil
            let file = e["file"] as? String ?? ""
            let pages = e["pages"] as? Int ?? 0
            let removed = e["removed"] as? Int ?? 0
            let name = (file as NSString).lastPathComponent
            lastMessage = "\(name): \(pages) Seite(n)" + (removed > 0 ? ", \(removed) leer entfernt" : "")
            notify("Scan fertig", lastMessage ?? "")
            refreshRecent()
        case "error":
            progress = nil
            lastMessage = "Fehler: \(e["message"] as? String ?? "?")"
            notify("Scan fehlgeschlagen", e["message"] as? String ?? "")
        case "notice":
            lastMessage = e["message"] as? String
            notify("iX500 Scan", lastMessage ?? "")
        default:
            break
        }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString,
                                                                     content: c, trigger: nil))
    }

    // MARK: Letzte Scans

    func refreshRecent() {
        let dir = ProcessInfo.processInfo.environment["SCANSNAP_DEMO_DIR"].map { URL(fileURLWithPath: $0) }
            ?? settings.outdirURL
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        recent = files.filter { $0.pathExtension.lowercased() == "pdf" }
            .compactMap { url in
                let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (url, d ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(24)
            .map { ScanResult(url: $0.0, date: $0.1, pages: PDFDocument(url: $0.0)?.pageCount ?? 0) }
    }
}
