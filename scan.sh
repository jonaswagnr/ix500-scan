#!/usr/bin/env bash
# ScanSnap iX500 -> durchsuchbares PDF (SANE fujitsu-Backend, nur USB)
#
#   ./scan.sh              einmal scannen (Stapel im Einzug)
#   ./scan.sh --watch      auf den blauen Scan-Knopf warten und bei jedem Druck scannen
#
# Einstellungen per Umgebungsvariable, z.B.:  MODE=Gray DPI=200 ./scan.sh

set -uo pipefail

MODE="${MODE:-Color}"            # Color | Gray | Lineart
DPI="${DPI:-300}"
SOURCE="${SOURCE:-ADF Duplex}"   # ADF Duplex | ADF Front
SKIP="${SKIP:-10}"               # Leerseiten-Schwelle in % (0 = aus)
LANGS="${LANGS:-deu+eng}"
OUTDIR="${OUTDIR:-$HOME/Documents/Scans}"

find_device() {
  scanimage -f '%d%n' 2>/dev/null | grep -m1 '^fujitsu:'
}

scan_once() {
  local dev="$1"
  local tmp; tmp="$(mktemp -d)"
  local out="$OUTDIR/$(date +%Y-%m-%d_%H%M%S).pdf"
  mkdir -p "$OUTDIR"

  echo "Scanne ($MODE, $DPI dpi, $SOURCE) ..."
  # Rückgabecode ignorieren: leerer Einzug am Ende meldet "out of documents"
  scanimage -d "$dev" \
    --source "$SOURCE" --mode "$MODE" --resolution "$DPI" \
    --swdeskew=yes --swcrop=yes --swskip "$SKIP" \
    --format=tiff --batch="$tmp/page%03d.tif" 2>&1 | grep -v '^Scanning\|^Scanned' || true

  shopt -s nullglob
  local pages=("$tmp"/page*.tif)
  if (( ${#pages[@]} == 0 )); then
    echo "Keine Seiten gescannt (Papier eingelegt?)."
    rm -rf "$tmp"; return 1
  fi

  echo "${#pages[@]} Seite(n) -> PDF + OCR ..."
  img2pdf "${pages[@]}" -o "$tmp/raw.pdf" &&
    ocrmypdf -q -l "$LANGS" --rotate-pages --optimize 1 "$tmp/raw.pdf" "$out"
  rm -rf "$tmp"
  echo "Fertig: $out"
}

button_pressed() {
  # Das fujitsu-Backend gibt den Knopf als Sensor-Option "--scan" aus
  scanimage -d "$1" -A 2>/dev/null | grep -E '^\s+--scan\[' | grep -q '\[yes\]'
}

dev="$(find_device)"
if [[ -z "$dev" ]]; then
  echo "Kein iX500 gefunden. Per USB angeschlossen und eingeschaltet (Einzug offen)?" >&2
  exit 1
fi
echo "Gerät: $dev"

if [[ "${1:-}" == "--watch" ]]; then
  echo "Warte auf Scan-Knopf (Strg+C zum Beenden) ..."
  while true; do
    if button_pressed "$dev"; then
      scan_once "$dev"
      echo "Warte auf Scan-Knopf ..."
    fi
    sleep 0.5
  done
else
  scan_once "$dev"
fi
