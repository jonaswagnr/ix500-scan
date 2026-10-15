#!/usr/bin/env bash
# Baut iX500 Scan.app (Swift-Paket + Python-Dienst im Bundle).
#   ./build.sh            -> build/iX500 Scan.app
#   ./build.sh install    -> zusätzlich nach /Applications kopieren
set -euo pipefail
cd "$(dirname "$0")"
ROOT=..
APP="build/iX500 Scan.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/IX500Scan"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/python/vens"
cp "$BIN" "$APP/Contents/MacOS/IX500Scan"
cp "$ROOT"/{scansnapd.py,pipeline.py,postprocess.py} "$APP/Contents/Resources/python/"
cp "$ROOT/vens/scansnap.py" "$APP/Contents/Resources/python/vens/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>iX500 Scan</string>
  <key>CFBundleDisplayName</key><string>iX500 Scan</string>
  <key>CFBundleIdentifier</key><string>com.jonaswagner.ix500scan</string>
  <key>CFBundleExecutable</key><string>IX500Scan</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>iX500 Scan verbindet sich per WLAN mit deinem ScanSnap iX500.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Gebaut: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x IX500Scan 2>/dev/null || true
  rm -rf "/Applications/iX500 Scan.app"
  cp -R "$APP" /Applications/
  echo "Installiert: /Applications/iX500 Scan.app"
fi
