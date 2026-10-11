#!/bin/sh
# Remove the queue, filter and PPD installed by install.sh.
# Usage: sudo ./uninstall.sh [queue-name]
set -e
QUEUE="${1:-SCX3400}"
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
lpadmin -x "$QUEUE" 2>/dev/null || echo "Queue '$QUEUE' not present."
rm -f /Library/Printers/SpliX/Filters/rastertoqpdl
rm -f /Library/Printers/PPDs/Contents/Resources/Samsung-SCX-3400-splix.ppd
rmdir /Library/Printers/SpliX/Filters /Library/Printers/SpliX 2>/dev/null || true
echo "Removed."
