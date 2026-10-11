#!/bin/sh
# Remove a queue created by install.sh, plus the filter and all SpliX PPDs.
# Usage: sudo ./uninstall.sh [queue-name ...]
set -e
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
for q in "$@"; do
    lpadmin -x "$q" 2>/dev/null && echo "Removed queue '$q'." || echo "Queue '$q' not present."
done
rm -f /Library/Printers/SpliX/Filters/rastertoqpdl
rm -f /Library/Printers/PPDs/Contents/Resources/SpliX-*.ppd
rm -f /Library/Printers/PPDs/Contents/Resources/Samsung-SCX-3400-splix.ppd  # pre-0.2 layout
rmdir /Library/Printers/SpliX/Filters /Library/Printers/SpliX 2>/dev/null || true
echo "Filter and PPDs removed."
