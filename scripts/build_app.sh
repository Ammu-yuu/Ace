#!/usr/bin/env bash
#
# Build a distributable Ace.app bundle.
#
# We package a real .app (not just the bare SwiftPM binary) because macOS ties
# microphone / speech-recognition permission to a bundle identity + Info.plist.
# The ad-hoc code signature gives TCC a stable identity to remember.
#
# Usage:  ./scripts/build_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Ace"
CONFIG="release"
PRODUCT="AcePet"   # SwiftPM executable target name

echo "▶ Building $PRODUCT ($CONFIG)…"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "▶ Assembling $APP_DIR…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$PRODUCT" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"

# Bundle placeholder assets if present.
if [ -d "$ROOT/assets" ]; then
    cp -R "$ROOT/assets" "$APP_DIR/Contents/Resources/assets"
fi

# Ad-hoc sign so mic/speech permissions attach to a stable identity.
echo "▶ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR" || echo "⚠ codesign failed (continuing anyway)"

echo "✔ Built $APP_DIR"
echo "   Launch it with:  open \"$APP_DIR\""
