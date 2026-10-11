#!/bin/sh
# Install the native arm64 SpliX filter and all SpliX PPDs, then — if a supported
# printer is reachable — create a CUPS queue for it.
#
# Usage: sudo ./install.sh [model] [device-uri] [queue-name]
#        ./install.sh --list
#
# model       PPD basename from dist/ppd, e.g. scx3400, ml1660, ph3160.
#             Omitted: guessed from the printers lpinfo discovers.
# device-uri  Omitted: the first discovered printer matching the model.
# queue-name  Omitted: the model name in upper case.
#
# The driver install never needs the printer to be online. Only the queue does;
# without one you can add the printer later in System Settings and pick your
# model by hand under "Select Software".
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
PPDSRC="$ROOT/dist/ppd"
FILTERDIR=/Library/Printers/SpliX/Filters
PPDDIR=/Library/Printers/PPDs/Contents/Resources

models() { ls "$PPDSRC" | sed 's/\.ppd$//'; }
# Longest names first, so ml2580n beats ml2580 and scx4623fw beats scx4623f.
models_by_length() { models | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-; }
# Device URIs lpinfo discovered.
uris() { lpinfo -v 2>/dev/null | awk '$2 ~ /:\/\// { print $2 }'; }
# Matching form of a URI: percent-decoded, lowercase, alphanumerics only -- so that
# "Samsung%20SCX-3400%20Series" matches the PPD named scx3400.
norm() { printf '%s' "$1" | sed 's/%20/ /g' | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9'; }

if [ "$1" = "--list" ]; then
    models | column -c 78 2>/dev/null || models
    exit 0
fi

[ "$(id -u)" = 0 ] || { echo "Run with sudo. Model list: ./install.sh --list"; exit 1; }

MODEL="$1"
URI="$2"
QUEUE="$3"

# --- driver: filter + every PPD. Works offline. ---
install -d -o root -g wheel -m 755 "$FILTERDIR"
install -o root -g wheel -m 755 "$ROOT/dist/rastertoqpdl" "$FILTERDIR/rastertoqpdl"
xattr -cr "$FILTERDIR/rastertoqpdl" 2>/dev/null || true
for ppd in "$PPDSRC"/*.ppd; do
    install -o root -g wheel -m 644 "$ppd" "$PPDDIR/SpliX-$(basename "$ppd")"
done
echo "Installed rastertoqpdl and $(models | wc -l | tr -d ' ') PPDs."

manual_hint() {
    echo
    echo "No queue was created. Add the printer in System Settings > Printers & Scanners,"
    echo "then under 'Select Software' pick your model (the SpliX PPDs are listed there)."
    echo "Or re-run this script with the printer switched on."
}

# --- queue: needs the printer to be discoverable ---
if [ -z "$MODEL" ]; then
    HAYSTACK=$(uris | while read -r u; do norm "$u"; echo; done)
    MODEL=$(models_by_length | while read -r m; do
        if printf '%s' "$HAYSTACK" | grep -qF -- "$m"; then printf '%s' "$m"; break; fi
    done)
    [ -n "$MODEL" ] && echo "Detected model: $MODEL"
fi
if [ -z "$MODEL" ]; then
    echo "No supported printer discovered."
    manual_hint
    exit 0
fi
[ -f "$PPDSRC/$MODEL.ppd" ] || { echo "Unknown model '$MODEL'. See ./install.sh --list"; exit 1; }

if [ -z "$URI" ]; then
    URI=$(uris | while read -r u; do
        if printf '%s' "$(norm "$u")" | grep -qF -- "$MODEL"; then printf '%s' "$u"; break; fi
    done)
fi
# lpinfo reports Bonjour devices with an empty path; CUPS wants a protocol there,
# and "auto" lets the dnssd backend pick one.
case "$URI" in dnssd://*/) URI="${URI}auto" ;; esac

if [ -z "$URI" ]; then
    echo "Printer '$MODEL' is not reachable right now."
    manual_hint
    exit 0
fi

[ -n "$QUEUE" ] || QUEUE=$(printf '%s' "$MODEL" | tr 'a-z' 'A-Z')
PPD="$PPDDIR/SpliX-$MODEL.ppd"
DESC=$(sed -n 's/^\*NickName: *"\(.*\)"/\1/p' "$PPD" | head -1)

lpadmin -p "$QUEUE" -E -v "$URI" -P "$PPD" -L "" -o printer-is-shared=false \
        -D "$DESC (SpliX arm64)"

echo "Queue '$QUEUE' created on $URI"
lpstat -p "$QUEUE"
echo
echo "If an old vendor queue for this printer is still around, remove it and set the default:"
echo "  lpstat -p"
echo "  sudo lpadmin -x <old-queue-name>"
echo "  lpoptions -d $QUEUE"
