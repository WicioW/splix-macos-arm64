# SpliX for Apple Silicon macOS

**This fixes Samsung printer drivers on Apple Silicon Macs (M1 and newer).** Samsung's
own driver package is Intel-only and no longer runs, so printing fails with *"The
printer software is not compatible with this device."* This replaces it with a driver
built for `arm64`, and does the same for scanning.

A native `arm64` CUPS driver for Samsung QPDL/SPL2 laser printers — and their Xerox,
Dell, Lexmark, Toshiba and HP rebrands — on macOS 27 ("Golden Gate") and later.
No Rosetta, no Docker, no vendor driver package.

104 printer models are supported, plus network scanning on the multifunction ones.
Only the **Samsung SCX-3400** has been verified on real hardware; the rest come from
upstream SpliX and should work.

## The problem

Samsung's last macOS driver (Samsung Printer Drivers v2.6, 2013) ships its CUPS filter
as an Intel-only binary:

```
$ file /Library/Printers/Samsung/Filters/rastertosec
Mach-O universal binary with 2 architectures: [x86_64] [i386]
```

macOS 27 no longer installs Rosetta 2 for macOS binaries — only `RosettaLinux`, which is
for x86_64 Linux guests in VMs. `cupsd` therefore cannot exec the filter, and every job
dies the moment the raster stream is handed over:

```
execv of /Library/Printers/Samsung/Filters/rastertosec failed. err:86, Bad CPU type in executable
cgpdftoraster: rasterWriteHeader: Unable to write raster stream header: Broken pipe
printer-state-reasons=com.apple.badarch-error
```

The Print Center shows **"The printer software is not compatible with this device."**
Reinstalling the vendor package does not help — the driver is fine, the system simply
cannot run it. Rosetta 2 is only a stopgap: Apple has announced its removal in macOS 28.

AirPrint is not an option either. An SCX-3400 advertises no AirPrint-compatible PDL:

```
pdl=application/octet-stream,application/x-QPDL
usb_CMD=MFG:Samsung;CMD:SPL,FWV,PIC,BDN,EXT;MDL:SCX-3400 Series;...
```

QPDL/SPL only — no PostScript, no PCL, no URF — so a generic driver cannot drive it.

## The solution

[SpliX](https://github.com/OpenPrinting/splix) is a GPL-2.0 CUPS driver for QPDL/SPL2
printers. It is C++ source, so it compiles natively for `arm64`:

```
$ file dist/rastertoqpdl
Mach-O 64-bit executable arm64

$ otool -L dist/rastertoqpdl
	/usr/lib/libcups.2.dylib
	/usr/lib/libcupsimage.2.dylib
	/usr/lib/libSystem.B.dylib
	/usr/lib/libc++.1.dylib
```

JBIG is linked statically, so the installed filter has no Homebrew runtime dependency.
One filter drives every model; only the PPD is model-specific.

## Install

```sh
sudo ./install.sh
```

That installs the driver and, if a supported printer is switched on and discoverable,
creates a queue for it:

```
Installed rastertoqpdl and 104 PPDs.
Detected model: scx3400
Queue 'SCX3400' created on dnssd://Samsung%20SCX-3400%20Series%20(SEC001599A59792)._printer._tcp.local./auto
```

| Path | What |
| --- | --- |
| `/Library/Printers/SpliX/Filters/rastertoqpdl` | the filter (`/usr/libexec/cups/filter` is SIP-protected) |
| `/Library/Printers/PPDs/Contents/Resources/SpliX-*.ppd` | one PPD per model, each with an absolute `*cupsFilter` path |

The driver half never needs the printer to be online. If no queue was created, add the
printer in **System Settings › Printers & Scanners** and pick your model by hand under
**Select Software** — the SpliX PPDs are listed there.

Everything can also be given explicitly:

```sh
./install.sh --list                      # the 104 model names
sudo ./install.sh ml1660                 # force the model, auto-discover the printer
sudo ./install.sh ml1660 socket://192.168.1.50:9100 Office
lpinfo -v                                # device URIs, if discovery fails
```

Then remove any old, broken vendor queue and make the new one the default:

```sh
lpstat -p
sudo lpadmin -x Samsung_SCX_3400_Series__SECXXXXXXXXXXXX_
lpoptions -d SCX3400
```

Uninstall with `sudo ./uninstall.sh [queue-name ...]`.

## Supported models

```
1100     1110     clp200   clp300   clp310   clp310n  clp315   clp500   clp510
clp550   clp600   clx216x  clx2170  clx3160  es180s   las100x  las11xx  laser10x
laser13x ljM433   ljM436   m2020    m2070    m262x    m267x    m283x    ml1510
ml1520   ml1610   ml1630   ml1640   ml1660   ml1670   ml1710   ml1740   ml1750
ml1860   ml1865   ml1865w  ml1910   ml1915   ml2010   ml2015   ml2150   ml2160
ml2165   ml2240   ml2250   ml2251   ml2510   ml2525   ml2525w  ml2550   ml2571
ml2580   ml2580n  ml3050   ml3051   ml3051nd ml3310   ml3310nd ml3471nd ml3560
ph3020   ph3052   ph3115   ph3116   ph3117   ph3120   ph3121   ph3122   ph3124
ph3130   ph3140   ph3150   ph3155   ph3160   ph3260   ph3420   ph3425   ph5500
ph6100   ph6110   scx3200  scx3400  scx4100  scx4200  scx4216f scx4300  scx4500
scx4521f scx4600  scx4623f scx4623fw scx5330n scx5530fn sf565p  wc3025   wc3119
wc3215   wc3225   wcpe114e wcpe16   x215mfp
```

SpliX does not support the older SPL1 protocol. If your model is absent, it is not a
QPDL printer.

## Build from source

`dist/` is prebuilt, but you can regenerate it:

```sh
./build.sh
```

Requirements: Xcode Command Line Tools and Homebrew (for `jbigkit`).

`build.sh` downloads SpliX from OpenPrinting, applies three macOS fixes, builds the
filter, and compiles every vendor's PPDs with the system `ppdc`:

1. macOS ships no `cups.pc`, so `tools/pkg-config` is a minimal shim answering for `cups`.
2. Upstream hardcodes MacPorts paths; they are rewritten to Homebrew for `jbigkit`.
3. `ppd/compile.sh` uses the GNU-only `sed -re`; BSD sed needs `-Ee`.

## Verify without printing

Run the whole filter chain by hand and inspect the output:

```sh
cupsfilter -m application/pdf /etc/hosts > /tmp/t.pdf
export PPD=dist/ppd/scx3400.ppd
/usr/libexec/cups/filter/cgpdftoraster 1 "$USER" test 1 "" /tmp/t.pdf > /tmp/t.raster
./dist/rastertoqpdl 1 "$USER" test 1 "" < /tmp/t.raster > /tmp/t.spl
```

A working chain reports the model and emits a PJL-wrapped QPDL stream:

```
DEBUG: SpliX Monochrome printer Samsung SCX-3400 with QPDL v. 3
DEBUG: SpliX Page 1 (4921x6350 on 5104x6600) has been successfully loaded into memory
PAGE: 1 1

$ xxd /tmp/t.spl | head -1
00000000: 1b25 2d31 3233 3435 5840 504a 4c20 4445  .%-12345X@PJL DE
```

## Scanning

The vendor scanner plugin has the same problem as the printer filter:

```
$ lipo -archs "/Library/Image Capture/Devices/Samsung Scanner.app/Contents/MacOS/Samsung Scanner"
i386 x86_64
```

So Image Capture, Preview and the Scan button in System Settings cannot drive these
machines on Apple Silicon. SANE's open-source `xerox_mfp` backend can — these printers
expose a scan service on TCP port 9400:

```sh
brew install sane-backends
./scan.sh
```

`scan.sh` writes `scan-<timestamp>.pdf` into the current directory:

```sh
./scan.sh -r 600 -m Color -o invoice.pdf   # resolution, mode, output
./scan.sh -h 192.168.1.22 -o page.png      # explicit host, PNG straight out
```

Without `-h` it reuses the Bonjour name of a printer queue CUPS already knows
(`SEC001599A59792.local`), so a DHCP lease change does not break it. It writes a private
SANE config per run and touches nothing global. PDF/JPEG conversion goes through `sips`,
so there is no dependency beyond `sane-backends`.

### A GUI for it

```sh
./make-app.sh
```

builds `Scan.app`: colour mode, resolution, file format (PDF, PNG or JPEG), then a
standard save panel, and the result opens when it is done. The extension you type in
the save panel wins over the format picked in the dialog. Format costs nothing in time
— at 300 dpi the scan itself takes about 70 seconds and the conversion about 0.1. No Terminal window. `make-app.sh` compiles
`scan-gui.applescript` with `osacompile` and copies `scan.sh` into the bundle's
`Resources`, so the app is self-contained and can be dragged to `/Applications`.
Re-run it after changing `scan.sh`.

The app is unsigned. Built locally it carries no quarantine flag and opens normally; if
you move it between machines, Gatekeeper will ask.

### Shipping the app to someone else

`Scan.app` is a build artifact and is not in the repository — `./make-app.sh` recreates
it in a second. To attach it to a GitHub release, zip it with `ditto`, which keeps the
bundle and its signature intact (a plain `zip` may not):

```sh
./make-app.sh
ditto -c -k --keepParent Scan.app Scan.app.zip
gh release create v1 Scan.app.zip --notes "Scanner GUI"
```

Anyone who downloads that zip in a browser gets it flagged with `com.apple.quarantine`,
and the app is only ad-hoc signed, not notarized by Apple. macOS will refuse to open it
until they go to System Settings › Privacy & Security and press **Open Anyway** once, or
run:

```sh
xattr -dr com.apple.quarantine Scan.app
```

Cloning the repository and building locally avoids all of that: git does not set the
quarantine attribute. Removing the warning for downloads needs a paid Apple Developer
ID and notarization; there is no middle option.

### Sleep

These printers drop off the network entirely in deep sleep — no ping, no Bonjour, no
scan port — and a scan would fail with a bare `Invalid argument`. `scan.sh` checks port
9400 first and, if nothing answers, sends a Wake-on-LAN magic packet and polls until the
printer is up (`-w secs`, default 60, `-w 0` to fail immediately).

The MAC comes from the host name: Samsung registers itself on Bonjour as `SEC` + its
MAC, so `SEC001599A59792.local` yields `00:15:99:A5:97:92`. For a host that does not
match that pattern the packet is skipped and only the polling remains.

To check the scanner by hand:

```sh
dns-sd -B _scanner._tcp local     # is it on the network?
nc -z -w 3 <host> 9400            # is the scan port open?
```

This is command-line only — it does not put the scanner back into Image Capture or
Preview. Doing that needs an ICA driver, which is a much bigger job than the print side.

## Troubleshooting

**Jobs still fail with `badarch-error`.** They are going to an old vendor queue. Check
`lpstat -d` and the queue name in `/var/log/cups/error_log`; delete the old queues and
set the SpliX one as the default.

**"No supported printer discovered."** The printer is asleep or off — these models drop
off Bonjour when they sleep. The driver still installed; wake the printer and re-run, or
add the queue by hand.

**The queue sits on "Looking for printer".** Same cause. `ping` it.

**`lpadmin` warns that printer drivers are deprecated.** Expected. CUPS will eventually
drop PPD support entirely; until then this works.

**Scan.app reports the printer as asleep while `./scan.sh` works.** macOS is blocking
the app's local-network access. A script run from Terminal inherits Terminal's
permission; an app needs its own. Open System Settings › Privacy & Security › Local
Network and switch **Scan** on.

If the toggle is already on and it still fails, check the signature:

```sh
codesign --verify --strict Scan.app
```

An app whose signature does not verify gets no local-network access even though its row
stays visible and switched on in System Settings. Connections then fail with
`No route to host` and even `ping` gets no reply, which is indistinguishable from a
sleeping printer — `scan.sh` writes what it actually saw to `$TMPDIR/scan-diag.log`.
Rebuild with `./make-app.sh`, which signs the bundle after it is assembled.

**Nothing comes out and the job completes.** Confirm the backend actually sent the data:
`lpstat -W completed -o` shows the byte count. A one-page job is roughly 15 KB.

## Licence

SpliX is GPL-2.0. `dist/rastertoqpdl` is a compiled SpliX binary and is covered by that
licence; the corresponding source is upstream at
[OpenPrinting/splix](https://github.com/OpenPrinting/splix), and the modifications
applied to it are the three `sed` edits in `build.sh`. The scripts in this repository
are GPL-2.0 as well. `scan.sh` only calls `sane-backends`, which Homebrew installs
separately; nothing from it is redistributed here.
