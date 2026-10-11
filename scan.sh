#!/bin/sh
# Scan over the network from a Samsung/Xerox multifunction, on Apple Silicon macOS.
#
# Usage: ./scan.sh [-h host] [-r dpi] [-m mode] [-o out]
#
#   -h  printer host or IP. Omitted: the Bonjour name of a printer CUPS already knows.
#   -r  resolution in dpi (default 300).
#   -m  Lineart, Gray (default) or Color.
#   -o  output file; the extension picks the format (default scan-<timestamp>.pdf).
#   -p  open the result when it is done (Preview, for a PDF).
#   -w  seconds to wait for a sleeping printer to wake (default 60, 0 to not wait).
#
# Needs sane-backends: brew install sane-backends
# The vendor scanner plugin (/Library/Image Capture/Devices/Samsung Scanner.app) is
# Intel-only and cannot run on Apple Silicon; SANE's xerox_mfp backend replaces it.
set -e

HOST=""; DPI=300; MODE=Gray; OUT=""; PREVIEW=0; WAIT=60
SCANPORT=9400
usage() { echo "Usage: $0 [-h host] [-r dpi] [-m Lineart|Gray|Color] [-o out.pdf] [-w secs] [-p]"; }

while getopts "h:r:m:o:w:p" opt; do
    case "$opt" in
        h) HOST=$OPTARG ;;
        r) DPI=$OPTARG ;;
        m) MODE=$OPTARG ;;
        o) OUT=$OPTARG ;;
        w) WAIT=$OPTARG ;;
        p) PREVIEW=1 ;;
        *) usage; exit 1 ;;
    esac
done

# A GUI launch (Scan.app, Finder, launchd) gets a minimal PATH without Homebrew on it.
case ":$PATH:" in
    *:/opt/homebrew/bin:*) ;;
    *) PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH ;;
esac

command -v scanimage >/dev/null || { echo "scanimage not found: brew install sane-backends"; exit 1; }

# Reuse the Bonjour host of a printer queue, e.g. SEC001599A59792.local — a name, so it
# survives a DHCP lease change.
[ -n "$HOST" ] || HOST=$(lpstat -v 2>/dev/null | sed -n 's/.*(\([A-Za-z0-9]*\))\..*/\1.local/p' | head -1)
if [ -z "$HOST" ]; then
    echo "No printer host found. Pass one with -h. To discover it:"
    echo "  dns-sd -B _scanner._tcp local"
    exit 1
fi

# These printers drop off the network in deep sleep: no ping, no Bonjour, nothing on
# the scan port. Wake them before scanning instead of failing with "Invalid argument".
printer_up() { nc -z -w 2 "$HOST" "$SCANPORT" >/dev/null 2>&1; }

# Samsung's Bonjour name is "SEC" + the MAC, so a magic packet can be built from the
# host name alone. Best effort: a no-op for other names, or if the printer ignores WOL.
wake_on_lan() {
    mac=$(printf '%s' "$HOST" | sed -n 's/^[Ss][Ee][Cc]\([0-9A-Fa-f]\{12\}\).*$/\1/p')
    [ -n "$mac" ] || return 0
    {
        printf '\377\377\377\377\377\377'
        n=0
        while [ "$n" -lt 16 ]; do
            c=1
            while [ "$c" -le 11 ]; do
                printf "\\$(printf '%03o' $((0x$(printf '%s' "$mac" | cut -c"$c"-$((c + 1))))))"
                c=$((c + 2))
            done
            n=$((n + 1))
        done
    } | nc -u -w 1 255.255.255.255 9 >/dev/null 2>&1 || true
}

# When the wait times out, record what this process could actually see. Run from a GUI
# app the answers can differ from a terminal: local-network access is granted per app.
DIAG="${TMPDIR:-/tmp}/scan-diag.log"
diagnose() {
    set +e   # every probe here is expected to fail; none of them may abort the script
    {
        echo "=== $(date) host=$HOST port=$SCANPORT"
        echo "whoami: $(id -un)   PATH=$PATH"
        echo "-- nc -z -w 3"; nc -z -v -w 3 "$HOST" "$SCANPORT" 2>&1; echo "exit=$?"
        echo "-- ping -c 2"; ping -c 2 -t 3 "$HOST" 2>&1 | tail -3
        echo "-- name resolution"; dscacheutil -q host -a name "$HOST" 2>&1 | head -5
        echo "-- this machine"; ipconfig getifaddr en0 2>&1
    } >> "$DIAG" 2>&1
    set -e
}

if ! printer_up; then
    echo "Printer is asleep, waking it..."
    waited=0
    until wake_on_lan; printer_up; do
        waited=$((waited + 3))
        if [ "$waited" -ge "$WAIT" ]; then
            diagnose
            echo "No answer from $HOST on port $SCANPORT after ${WAIT}s."
            echo "Press any button on the printer to wake it, then try again."
            echo "Details: $DIAG"
            exit 1
        fi
    done
    echo "Printer is up."
fi

[ -n "$OUT" ] || OUT="scan-$(date +%Y%m%d-%H%M%S).pdf"
# A name typed without an extension (the save panel allows it) would leave sips with
# no format to convert to.
case "$(basename "$OUT")" in *.*) ;; *) OUT="$OUT.pdf" ;; esac
EXT=$(printf '%s' "${OUT##*.}" | tr 'A-Z' 'a-z')
[ "$EXT" = jpg ] && EXT=jpeg

# A private SANE config: just this backend, just this host. Nothing global is touched.
CFG=$(mktemp -d)
trap 'rm -rf "$CFG"' EXIT
printf 'xerox_mfp\n' > "$CFG/dll.conf"
printf 'tcp %s\n' "$HOST" > "$CFG/xerox_mfp.conf"
export SANE_CONFIG_DIR="$CFG"

echo "Scanning from $HOST, ${DPI}dpi, $MODE..."
scanimage -d "xerox_mfp:tcp $HOST" --resolution "$DPI" --mode "$MODE" \
          --format=png -o "$CFG/page.png"

if [ "$EXT" = png ]; then
    cp "$CFG/page.png" "$OUT"
else
    sips -s format "$EXT" "$CFG/page.png" --out "$OUT" >/dev/null
fi
echo "Wrote $OUT"
[ "$PREVIEW" = 1 ] && open "$OUT"
exit 0
