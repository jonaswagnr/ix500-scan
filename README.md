# ScanSnap Lite

Eigene Scan-Software für den **Fujitsu/PFU ScanSnap iX500** auf macOS, weil ScanSnap Home 3.7 nicht mehr gepflegt wird und unter macOS 27 hängt.

- **Per WLAN** über das nachgebaute VENS-Protokoll ([bramheerink/scansnap](https://github.com/bramheerink/scansnap), in `vens/` eingebunden und für macOS erweitert)
- **Per USB** über SANE (`scan.sh`)
- **Mac-App** mit Fenster und Menüleiste (`app/`, SwiftUI); die Scan-Taste am Gerät startet den Scan
- Ergebnis: durchsuchbares PDF, gedreht, zugeschnitten, ohne Leerseiten, mit OCR über `ocrmypdf`

## Voraussetzungen

```bash
brew install sane-backends ocrmypdf img2pdf tesseract-lang
```

Python 3 mit Pillow (`/usr/bin/python3`), Xcode 15+ für die App.

## Einmalig: Kopplungsschlüssel

Der Scanner verlangt im Handshake zwei Werte, die nur ScanSnap Home kennt:

- einen **Kopplungsschlüssel** (12 Zeichen)
- die **HostID** des gekoppelten Rechners (8 Byte)

Mitschneiden, während ScanSnap Home sich verbindet:

```bash
sudo tcpdump -i en0 -w handshake.pcap -c 40 'tcp dst port 53219 and host <SCANNER-IP>'
# ScanSnap Home starten, Scan auslösen, danach ScanSnap Home beenden
python3 extract_key.py handshake.pcap     # -> ~/.config/scansnap/{key,hostid}
python3 vens/scansnap.py status -s <SCANNER-IP>   # erwartet: err=0
```

## Benutzen

```bash
app/build.sh install                      # App bauen und nach /Applications kopieren
./scan_wifi.py --mode gray --dpi 200      # Kommandozeile, WLAN
./scan.sh                                 # Kommandozeile, USB (SANE)
```

## Aufbau

| Datei | Zweck |
|---|---|
| `vens/scansnap.py` | WLAN-Treiber (VENS); ergänzt um macOS-Unterstützung, HostID, lokale Zeit/Zeitzone im Handshake und einen Callback pro Seite |
| `scansnapd.py` | Hintergrunddienst für die App: hält die Sitzung, fragt den Status ab (0xC2), erkennt die Scan-Taste, JSON über stdin/stdout |
| `pipeline.py` | Einstellungen, Leerseiten, PDF, OCR |
| `postprocess.py` | 180° drehen, Rand anhand des Kantenschattens zuschneiden, Farbmodus und dpi |
| `scan_wifi.py` | WLAN-Scan über die Kommandozeile |
| `scan.sh` | USB-Scan über SANE |
| `extract_key.py` | Schlüssel und HostID aus einem pcap-Mitschnitt |
| `button_probe.py`, `button_poll.py` | Werkzeuge, mit denen die Scan-Taste untersucht wurde |
| `app/` | SwiftUI-App (Swift Package, `build.sh` erzeugt das `.app`-Bundle) |

## Protokoll-Erkenntnisse (zusätzlich zu `vens/PROTOCOL`)

- **Handshake-Bytes 108–115** enthalten die HostID des gekoppelten Rechners. Ist sie falsch, antwortet der Scanner mit `-7`.
- **Bytes 100–106** tragen Datum und Uhrzeit, **116–119** den UTC-Offset in Sekunden (UTC − lokal).
- **0xC2 (GET HARDWARE STATUS):** Byte 43 Bit `0x80` bedeutet Einzug leer, Byte 44 Bit `0x01` Scan-Taste gedrückt.
- Der Scanner beendet eine offene Sitzung nach etwa 40 s.
- Per WLAN kommen die Bilder immer als Farbe, 300 dpi, 180° gedreht, mit Scanner-Hintergrund.

## Lizenz

GPL-2.0, wie das eingebundene [bramheerink/scansnap](https://github.com/bramheerink/scansnap) (Stand `5706688`).
