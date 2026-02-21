#!/usr/bin/env bash
# Rebuild ClawApp and relaunch the .app bundle.
# Usage: ./scripts/rebuild-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT_DIR="$ROOT/client"
APP="$ROOT/ClawApp.app"
BINARY="$APP/Contents/MacOS/ClawApp"

# Create the bundle structure if it doesn't exist yet.
if [[ ! -d "$APP/Contents/MacOS" ]]; then
  mkdir -p "$APP/Contents/MacOS"
  cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClawApp</string>
    <key>CFBundleIdentifier</key>
    <string>app.discoclaw.ClawApp</string>
    <key>CFBundleName</key>
    <string>ClawApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF
fi

echo "▶ Building ClawApp…"
swift build --package-path "$CLIENT_DIR" -c debug

# Resolve the architecture-specific build output path.
ARCH=$(uname -m)
BUILD_BIN="$CLIENT_DIR/.build/${ARCH}-apple-macosx/debug/ClawApp"

echo "▶ Stopping previous instance…"
pkill -x ClawApp 2>/dev/null || true
sleep 0.5

echo "▶ Installing binary…"
cp "$BUILD_BIN" "$BINARY"

echo "▶ Launching…"
open "$APP"
echo "✓ Done — $APP"
