#!/usr/bin/env python3
"""ScanSnap iX500 per WLAN -> durchsuchbares PDF (Kommandozeile).

    ./scan_wifi.py                   mit den Einstellungen der App scannen
    ./scan_wifi.py --mode gray --dpi 200 --quality 60
    ./scan_wifi.py --keep-blank --no-ocr --no-crop

Einstellungen: ~/Library/Application Support/iX500 Scan/settings.json
Voraussetzung: ~/.config/scansnap/key und ~/.config/scansnap/hostid
"""
import argparse, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "vens"))
sys.path.insert(0, HERE)
import scansnap as ss  # noqa: E402
import pipeline  # noqa: E402


def main():
    st = pipeline.load_settings()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-s", "--scanner", default=os.environ.get("SCANNER_IP") or st["scanner_ip"])
    ap.add_argument("-o", "--output", help="Ziel-PDF")
    ap.add_argument("--mode", choices=["color", "gray", "bw"], default=st["mode"])
    ap.add_argument("--dpi", type=int, choices=[150, 200, 300], default=st["dpi"])
    ap.add_argument("--quality", type=int, default=st["quality"], help="JPEG-Qualität 40..95")
    ap.add_argument("--keep-blank", action="store_true")
    ap.add_argument("--no-ocr", action="store_true")
    ap.add_argument("--no-crop", action="store_true")
    ap.add_argument("--force", action="store_true", help="Papierprüfung überspringen")
    ap.add_argument("-d", "--debug", action="store_true")
    a = ap.parse_args()
    st.update(mode=a.mode, dpi=a.dpi, quality=a.quality)
    if a.keep_blank: st["remove_blank"] = False
    if a.no_ocr: st["ocr"] = False
    if a.no_crop: st["crop"] = False

    key = ss.load_key()
    if not key or not ss.load_hostid():
        sys.exit("Schlüssel/HostID fehlen in ~/.config/scansnap/ (siehe extract_key.py).")
    ip = a.scanner or next(iter(sorted(ss.find_scanners())), None)
    if not ip:
        sys.exit("Kein Scanner im WLAN gefunden. IP mit -s angeben.")
    my_ip, (mac, _) = ss.local_ip_toward(ip), ss.wifi_mac_toward(ip)

    if not a.force:
        status = ss.read_status(ip, mac, my_ip, key)
        if status is None:
            sys.exit("Scanner belegt. ScanSnap Home bzw. die App beenden oder 'vens/scansnap.py release'.")
        if ss.paper_present(status.get("C2", b"")) is False:
            sys.exit("Einzug ist leer, bitte Papier einlegen.")

    print(f"Scanne über {ip} ...")
    raw = ss.scan(ip, key, verbose=a.debug, on_page=lambda n: print(f"  Seite {n}"))
    if not raw:
        sys.exit("Keine Seiten empfangen.")
    out, n, removed = pipeline.build_pdf(raw, st, a.output,
                                         emit=lambda ev, **k: print(f"  {k.get('step', ev)} ..."))
    print(f"Fertig: {out} ({n} Seiten, {removed} leer entfernt)")


if __name__ == "__main__":
    main()
