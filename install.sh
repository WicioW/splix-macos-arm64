#!/bin/sh
# Install the native arm64 SpliX filter + SCX-3400 PPD and create a CUPS queue.
# Usage: sudo ./install.sh [device-uri] [queue-name]
# With no device-uri, the printer is auto-discovered via lpinfo. Idempotent.
set -e

SRC="$(cd "$(dirname "$0")/dist" && pwd)"
FILTERDIR=/Library/Printers/SpliX/Filters
PPDDIR=/Library/Printers/PPDs/Contents/Resources
PPD="$PPDDIR/Samsung-SCX-3400-splix.ppd"
QUEUE="${2:-SCX3400}"

[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }

URI="$1"
if [ -z "$URI" ]; then
    URI=$(lpinfo -v | awk '/SCX-3400/ { print $2; exit }')
fi
[ -n "$URI" ] || { echo "Printer not found. Pass the device URI explicitly (see: lpinfo -v)."; exit 1; }

install -d -o root -g wheel -m 755 "$FILTERDIR"
install -o root -g wheel -m 755 "$SRC/rastertoqpdl" "$FILTERDIR/rastertoqpdl"
install -o root -g wheel -m 644 "$SRC/Samsung-SCX-3400-splix.ppd" "$PPD"
xattr -cr "$FILTERDIR/rastertoqpdl" 2>/dev/null || true

lpadmin -p "$QUEUE" -E -v "$URI" -P "$PPD" \
        -D "Samsung SCX-3400 (SpliX arm64)" -L "" -o printer-is-shared=false

echo "Queue '$QUEUE' created on $URI"
lpstat -p "$QUEUE"
echo
echo "Remove the old vendor queues if they are still present, then set the default:"
echo "  lpstat -p | grep -i samsung"
echo "  sudo lpadmin -x <old-queue-name>"
echo "  lpoptions -d $QUEUE"
