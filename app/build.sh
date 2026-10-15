#!/usr/bin/env bash
# Baut ScanSnap Lite.app (Swift-Paket + Python-Dienst im Bundle).
#   ./build.sh            -> build/ScanSnap Lite.app
#   ./build.sh install    -> zusätzlich nach /Applications kopieren
set -euo pipefail
cd "$(dirname "$0")"
ROOT=..
APP="build/ScanSnap Lite.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ScanSnapLite"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/python/vens"
cp "$BIN" "$APP/Contents/MacOS/ScanSnapLite"
cp "$ROOT"/{scansnapd.py,pipeline.py,postprocess.py} "$APP/Contents/Resources/python/"
cp "$ROOT/vens/scansnap.py" "$APP/Contents/Resources/python/vens/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ScanSnap Lite</string>
  <key>CFBundleDisplayName</key><string>ScanSnap Lite</string>
  <key>CFBundleIdentifier</key><string>com.jonaswagner.scansnaplite</string>
  <key>CFBundleExecutable</key><string>ScanSnapLite</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>ScanSnap Lite verbindet sich per WLAN mit deinem ScanSnap iX500.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Gebaut: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x ScanSnapLite 2>/dev/null || true
  rm -rf "/Applications/ScanSnap Lite.app"
  cp -R "$APP" /Applications/
  echo "Installiert: /Applications/ScanSnap Lite.app"
fi
