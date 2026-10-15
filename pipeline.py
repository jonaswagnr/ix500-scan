"""Gemeinsame Scan-Pipeline für scan_wifi.py und scansnapd.py.

Roh-JPEGs -> drehen/zuschneiden/Modus -> Leerseiten raus -> PDF -> OCR -> Ablage.
"""
import json, os, subprocess, tempfile, time
from io import BytesIO

from PIL import Image

import postprocess

SETTINGS_PATH = os.path.expanduser("~/Library/Application Support/ScanSnapLite/settings.json")

DEFAULTS = {
    "scanner_ip": "",            # leer = automatisch suchen
    "mode": "color",             # color | gray | bw
    "dpi": 300,                  # 150 | 200 | 300
    "quality": 75,               # JPEG-Qualität 40..95
    "crop": True,
    "remove_blank": True,
    "blank_threshold": 0.003,    # Anteil dunkler Pixel, unter dem eine Seite leer ist
    "ocr": True,
    "ocr_langs": "deu+eng",
    "optimize": 2,               # ocrmypdf --optimize 0..3
    "outdir": "~/Documents/Scans",
    "filename": "%Y-%m-%d_%H%M%S",
    "open_after": False,
    "button_scan": True,         # Scan-Taste am Gerät startet den Scan
}

# Homebrew-Tools auch finden, wenn die App ohne Shell-PATH startet
os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + os.environ.get("PATH", "")


def load_settings():
    s = dict(DEFAULTS)
    try:
        with open(SETTINGS_PATH) as f:
            s.update(json.load(f))
    except (OSError, ValueError):
        pass
    return s


def is_blank(image_bytes, threshold=0.003):
    """Leer, wenn weniger als `threshold` der Pixel (ohne 5 % Rand) dunkel sind."""
    im = Image.open(BytesIO(image_bytes)).convert("L")
    im.thumbnail((400, 400))
    w, h = im.size
    mx, my = int(w * 0.05), int(h * 0.05)
    px = list(im.crop((mx, my, w - mx, h - my)).getdata())
    dark = sum(1 for p in px if p < 200)
    return dark / len(px) < threshold


def unique_path(path):
    base, ext = os.path.splitext(path)
    n = 2
    while os.path.exists(path):
        path = f"{base}_{n}{ext}"; n += 1
    return path


def build_pdf(raw_pages, settings, output=None, emit=lambda *a, **k: None):
    """Verarbeitet Roh-JPEGs zu einem PDF. Gibt (Pfad, Seiten, entfernt) zurück."""
    emit("processing", step="images")
    pages = [postprocess.process(p, crop=settings["crop"], mode=settings["mode"],
                                 dpi=int(settings["dpi"]), quality=int(settings["quality"]))
             for p in raw_pages]
    if settings["remove_blank"]:
        kept = [p for p in pages if not is_blank(p[0], settings["blank_threshold"])]
    else:
        kept = pages
    removed = len(pages) - len(kept)
    if not kept:
        raise RuntimeError("Alle Seiten waren leer.")

    outdir = os.path.expanduser(settings["outdir"])
    os.makedirs(outdir, exist_ok=True)
    out = output or unique_path(os.path.join(outdir, time.strftime(settings["filename"]) + ".pdf"))

    with tempfile.TemporaryDirectory() as tmp:
        files = []
        for i, (data, ext) in enumerate(kept):
            fn = os.path.join(tmp, f"p{i:03d}.{ext}")
            with open(fn, "wb") as f:
                f.write(data)
            files.append(fn)
        raw = os.path.join(tmp, "raw.pdf")
        subprocess.run(["img2pdf", *files, "-o", raw], check=True, capture_output=True)
        if settings["ocr"]:
            emit("processing", step="ocr")
            r = subprocess.run(["ocrmypdf", "-q", "-l", settings["ocr_langs"], "--rotate-pages",
                                "--deskew", "--optimize", str(settings["optimize"]), raw, out],
                               capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError("Texterkennung fehlgeschlagen: " + r.stderr.strip()[-300:])
        else:
            os.replace(raw, out)
    return out, len(kept), removed
