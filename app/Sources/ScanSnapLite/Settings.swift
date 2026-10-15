import Foundation

/// Einstellungen, geteilt mit dem Python-Dienst über settings.json (gleiche Schlüssel wie pipeline.DEFAULTS).
struct ScanSettings: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case color, gray, bw
        var id: String { rawValue }
        var label: String {
            switch self {
            case .color: "Farbe"
            case .gray: "Graustufen"
            case .bw: "Schwarzweiß"
            }
        }
    }

    var scannerIP = ""
    var mode = Mode.color
    var dpi = 300
    var quality = 75
    var crop = true
    var removeBlank = true
    var blankThreshold = 0.003
    var ocr = true
    var ocrLangs = "deu+eng"
    var optimize = 2
    var outdir = "~/Documents/Scans"
    var filename = "%Y-%m-%d_%H%M%S"
    var openAfter = false
    var buttonScan = true

    enum CodingKeys: String, CodingKey {
        case scannerIP = "scanner_ip", mode, dpi, quality, crop
        case removeBlank = "remove_blank", blankThreshold = "blank_threshold"
        case ocr, ocrLangs = "ocr_langs", optimize, outdir, filename
        case openAfter = "open_after", buttonScan = "button_scan"
    }

    init() {}

    // Fehlende Schlüssel (ältere Datei) fallen auf Standardwerte zurück
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScanSettings()
        scannerIP = try c.decodeIfPresent(String.self, forKey: .scannerIP) ?? d.scannerIP
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? d.mode
        dpi = try c.decodeIfPresent(Int.self, forKey: .dpi) ?? d.dpi
        quality = try c.decodeIfPresent(Int.self, forKey: .quality) ?? d.quality
        crop = try c.decodeIfPresent(Bool.self, forKey: .crop) ?? d.crop
        removeBlank = try c.decodeIfPresent(Bool.self, forKey: .removeBlank) ?? d.removeBlank
        blankThreshold = try c.decodeIfPresent(Double.self, forKey: .blankThreshold) ?? d.blankThreshold
        ocr = try c.decodeIfPresent(Bool.self, forKey: .ocr) ?? d.ocr
        ocrLangs = try c.decodeIfPresent(String.self, forKey: .ocrLangs) ?? d.ocrLangs
        optimize = try c.decodeIfPresent(Int.self, forKey: .optimize) ?? d.optimize
        outdir = try c.decodeIfPresent(String.self, forKey: .outdir) ?? d.outdir
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? d.filename
        openAfter = try c.decodeIfPresent(Bool.self, forKey: .openAfter) ?? d.openAfter
        buttonScan = try c.decodeIfPresent(Bool.self, forKey: .buttonScan) ?? d.buttonScan
    }

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ScanSnapLite/settings.json")

    var outdirURL: URL {
        URL(fileURLWithPath: (outdir as NSString).expandingTildeInPath)
    }

    static func load() -> ScanSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(ScanSettings.self, from: data) else { return ScanSettings() }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Self.fileURL, options: .atomic)
    }
}
