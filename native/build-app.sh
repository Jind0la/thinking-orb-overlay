#!/bin/bash
# build-app.sh — compile + bundle + codesign Thinking Orb.app.
# Vorlage: 10-hermes-agent-screen (build-app.sh). Kein Screen-Recording nötig,
# trotzdem mit vorhandener Dev-Identität signieren (nie ad-hoc).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${HOME}/.hermes/thinking-orb"
APP_DIR="$INSTALL_DIR/app"
BUNDLE="$APP_DIR/Thinking Orb.app"
BINARY="$APP_DIR/thinking-orb-app"
SOURCE="$PROJECT_DIR/thinking-orb-app.swift"
CERT="Agent Screen Dev"
IDENTIFIER="ai.hermes.thinking-orb"
PLIST="$BUNDLE/Contents/Info.plist"

cd "$PROJECT_DIR"

say()  { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[build]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

ensure_cert() {
  if security find-certificate -c "$CERT" >/dev/null 2>&1; then
    return 0
  fi
  die "codesigning identity '$CERT' not found (siehe 10-hermes-agent-screen/native/build-app.sh — einmalig im Keychain anlegen)"
}

write_info_plist() {
  mkdir -p "$BUNDLE/Contents"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Thinking Orb</string>
	<key>CFBundleExecutable</key>
	<string>thinking-orb-app</string>
	<key>CFBundleIdentifier</key>
	<string>${IDENTIFIER}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Thinking Orb</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST
}

check() {
  [ -d "$BUNDLE" ]                       || die "bundle missing: $BUNDLE"
  [ -x "$BUNDLE/Contents/MacOS/thinking-orb-app" ] || die "binary missing inside bundle"
  [ -f "$PLIST" ]                        || die "Info.plist missing"
  grep -q "$IDENTIFIER" "$PLIST"         || die "Info.plist missing bundle id $IDENTIFIER"
  codesign --verify --deep "$BUNDLE" 2>/dev/null || die "invalid signature (codesign --verify)"
  echo "Bundle + signature OK: $BUNDLE"
}

if [ "${1:-}" = "--check" ]; then
  check
  exit 0
fi

[ -f "$SOURCE" ] || die "source missing: $SOURCE"
ensure_cert

mkdir -p "$APP_DIR" "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

HOST_ARCH="$(uname -m)"
say "compiling ${SOURCE}..."
if [ "$HOST_ARCH" = "arm64" ]; then
  swiftc -O -target arm64-apple-macos14.0 "$SOURCE" -o "$BINARY-arm64"
  if swiftc -O -target x86_64-apple-macos14.0 "$SOURCE" -o "$BINARY-x86_64" 2>/tmp/thinking-orb-x86-build.log; then
    lipo -create "$BINARY-arm64" "$BINARY-x86_64" -o "$BINARY"
    rm -f "$BINARY-arm64" "$BINARY-x86_64"
    say "universal binary (arm64 + x86_64)"
  else
    mv "$BINARY-arm64" "$BINARY"
    rm -f "$BINARY-x86_64"
    say "arm64-only (x86_64 cross-compile unavailable)"
  fi
else
  swiftc -O -target x86_64-apple-macos14.0 "$SOURCE" -o "$BINARY"
fi

say "assembling bundle..."
cp "$BINARY" "$BUNDLE/Contents/MacOS/thinking-orb-app"
chmod +x "$BUNDLE/Contents/MacOS/thinking-orb-app"
write_info_plist

say "signing with '$CERT'..."
codesign --force --sign "$CERT" --timestamp=none "$BUNDLE"

check
say "done. start: $PROJECT_DIR/thinking-orb.sh"
