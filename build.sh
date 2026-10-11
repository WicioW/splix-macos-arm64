#!/bin/sh
# Build a native arm64 SpliX rastertoqpdl filter and the Samsung SCX-3400 PPD on macOS.
# Output goes to dist/. No sudo needed; see install.sh for installation.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/build"
SRC="$WORK/splix-master"
TARBALL=https://github.com/OpenPrinting/splix/archive/refs/heads/master.tar.gz
FILTERPATH=/Library/Printers/SpliX/Filters/rastertoqpdl

command -v brew >/dev/null || { echo "Homebrew required (jbigkit)."; exit 1; }
xcrun --show-sdk-path >/dev/null 2>&1 || { echo "Xcode Command Line Tools required."; exit 1; }
brew list --formula 2>/dev/null | grep -qx jbigkit || brew install jbigkit

rm -rf "$WORK"
mkdir -p "$WORK"
curl -sSL "$TARBALL" | tar xz -C "$WORK"

# macOS fixes:
#  1. no cups.pc ships with macOS -> tools/pkg-config shim answers for "cups"
#  2. upstream hardcodes MacPorts paths -> point at Homebrew for jbigkit
#  3. ppd/compile.sh uses GNU "sed -re" -> BSD sed wants "-Ee"
sed -i '' \
    -e 's|-I/opt/local/include|-I/opt/homebrew/include|' \
    -e 's|-L/opt/local/lib|-L/opt/homebrew/lib|' \
    "$SRC/module.mk"
sed -i '' 's/sed -re/sed -Ee/' "$SRC/ppd/compile.sh"

PATH="$ROOT/tools:$PATH" make -C "$SRC"

# Generate PPDs from the driver source with the system ppdc.
( cd "$SRC/ppd" && sh compile.sh samsung.drv.in drv && mkdir -p out && ppdc -d out samsung.drv )

mkdir -p "$ROOT/dist"
cp "$SRC/optimized/rastertoqpdl" "$ROOT/dist/rastertoqpdl"
# Point the PPD at the absolute install path: /usr/libexec/cups/filter is SIP-protected,
# so the filter lives under /Library/Printers instead.
sed "s|^\*cupsFilter: \"application/vnd.cups-raster 0 rastertoqpdl\"|*cupsFilter: \"application/vnd.cups-raster 0 $FILTERPATH\"|" \
    "$SRC/ppd/out/scx3400.ppd" > "$ROOT/dist/Samsung-SCX-3400-splix.ppd"

file "$ROOT/dist/rastertoqpdl"
grep -a '^\*cupsFilter' "$ROOT/dist/Samsung-SCX-3400-splix.ppd"
echo "Built. PPDs for every other SpliX model are in build/splix-master/ppd/out/."
