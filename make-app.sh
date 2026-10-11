#!/bin/sh
# Build Scan.app, a self-contained GUI front end for scan.sh.
# The script is copied into the bundle, so the app can be moved to /Applications.
# Re-run this after changing scan.sh.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/Scan.app}"
BUNDLE_ID=org.splix.scan

rm -rf "$APP"
osacompile -o "$APP" "$ROOT/scan-gui.applescript"

# Everything that changes the bundle must happen before signing: osacompile signs its
# output, and a later edit to Resources or Info.plist invalidates that signature. An
# app whose signature does not verify gets no local-network access, whatever the
# toggle in System Settings says -- which looks exactly like a sleeping printer.
cp "$ROOT/scan.sh" "$APP/Contents/Resources/scan.sh"
chmod +x "$APP/Contents/Resources/scan.sh"

PL="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Scan" "$PL" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PL" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PL" >/dev/null

# Ad-hoc signature, last step.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

if ! codesign --verify --strict "$APP" 2>&1; then
    echo "Signature does not verify; the app would be denied local-network access." >&2
    exit 1
fi

echo "Built $APP"
codesign -d --verbose=1 "$APP" 2>&1 | grep -i "^Identifier"
