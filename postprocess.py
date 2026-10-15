"""Nachbearbeitung der Roh-JPEGs vom iX500 (WLAN): drehen und Rand abschneiden."""
from io import BytesIO
from statistics import median

from PIL import Image, ImageStat

EDGE_SEARCH = 0.05   # Blattkante in den äußeren 5 % je Seite suchen (Textzeilen weiter innen ignorieren)
EDGE_DIP = 12        # so viel dunkler als üblich muss der Kantenschatten sein
EDGE_FALLBACK = 15   # ohne erkannte Kante: fester Randstreifen (1/4-Auflösung, ~5 mm)
EDGE_MARGIN = 2      # Pixel (in 1/4-Auflösung), die hinter dem Schatten zusätzlich weg kommen


def _profile(im, axis):
    """Mittlere Helligkeit je Spalte (axis=0) oder Zeile (axis=1), nur mittlere 60 %."""
    w, h = im.size
    if axis == 0:
        y0, y1 = int(h * 0.2), int(h * 0.8)
        return [ImageStat.Stat(im.crop((x, y0, x + 1, y1))).mean[0] for x in range(w)]
    x0, x1 = int(w * 0.2), int(w * 0.8)
    return [ImageStat.Stat(im.crop((x0, y, x1, y + 1))).mean[0] for y in range(h)]


def _edge(profile, from_end):
    """Index hinter dem Kantenschatten auf einer Seite, oder None."""
    n = len(profile)
    span = int(n * EDGE_SEARCH)
    idx = range(n - 1, n - 1 - span, -1) if from_end else range(span)
    vals = [profile[i] for i in idx]
    base = median(profile)
    lo = min(vals)
    if lo > base - EDGE_DIP:
        # kein Schatten: evtl. Helligkeitssprung grauer Hintergrund -> weißes Papier
        if vals[0] <= base - 4:
            step = next((k for k, v in enumerate(vals) if v >= base - 2), None)
            if step is not None:
                return idx[min(step + EDGE_MARGIN, len(vals) - 1)]
        return None
    # äußerste Stelle, die deutlich dunkler ist, dann bis zum Ende des Schattens
    pos = next(k for k, v in enumerate(vals) if v <= base - EDGE_DIP)
    while pos + 1 < len(vals) and vals[pos + 1] <= base - EDGE_DIP / 2:
        pos += 1
    pos += EDGE_MARGIN
    return idx[min(pos, len(vals) - 1)]


def crop_box(img):
    """Zuschnitt (links, oben, rechts, unten) anhand der Kantenschatten."""
    small = img.convert("L")
    scale = 4
    small = small.resize((small.width // scale, small.height // scale))
    cols, rows = _profile(small, 0), _profile(small, 1)
    def pick(v, fallback):
        return v if v is not None else fallback
    left = pick(_edge(cols, False), EDGE_FALLBACK)
    right = pick(_edge(cols, True), len(cols) - EDGE_FALLBACK)
    top = pick(_edge(rows, False), EDGE_FALLBACK)
    bottom = pick(_edge(rows, True), len(rows) - EDGE_FALLBACK)
    w, h = img.size
    box = (left * scale, top * scale, min(right * scale, w), min(bottom * scale, h))
    # Plausibilität: nicht mehr als 30 % pro Achse wegschneiden
    if box[2] - box[0] < w * 0.7 or box[3] - box[1] < h * 0.7:
        return (0, 0, w, h)
    return box


SCAN_DPI = 300  # der Scanner liefert per WLAN immer 300 dpi


def process(jpeg, rotate=180, crop=True, mode="color", dpi=300, quality=80, bw_threshold=160):
    """Roh-JPEG -> (bytes, ext): gedreht, zugeschnitten, im gewünschten Modus.

    mode: "color" | "gray" | "bw"; dpi <= 300 wird herunterskaliert.
    Farbe/Graustufen werden JPEG, Schwarzweiß wird 1-Bit-PNG.
    """
    img = Image.open(BytesIO(jpeg))
    img.load()
    if crop:
        img = img.crop(crop_box(img))
    if rotate:
        img = img.rotate(rotate, expand=True)
    if dpi < SCAN_DPI:
        f = dpi / SCAN_DPI
        img = img.resize((round(img.width * f), round(img.height * f)), Image.LANCZOS)
    out = BytesIO()
    if mode == "bw":
        img = img.convert("L").point(lambda p: 255 if p > bw_threshold else 0).convert("1")
        img.save(out, "PNG", dpi=(dpi, dpi), optimize=True)
        return out.getvalue(), "png"
    img = img.convert("L" if mode == "gray" else "RGB")
    img.save(out, "JPEG", quality=quality, dpi=(dpi, dpi), optimize=True)
    return out.getvalue(), "jpg"
