# Samsung SCX-3400 on Apple Silicon macOS (SpliX, native arm64)

A native `arm64` CUPS filter and PPD that make the Samsung SCX-3400 series print on
macOS 27 ("Golden Gate") and later, without Rosetta, without Docker, and without the
discontinued Samsung driver package.

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
Reinstalling the Samsung package does not help — the driver is fine, the system simply
cannot run it. Rosetta 2 is only a stopgap: Apple has announced its removal in macOS 28.

AirPrint is not an option either. The printer advertises no AirPrint-compatible PDL:

```
pdl=application/octet-stream,application/x-QPDL
usb_CMD=MFG:Samsung;CMD:SPL,FWV,PIC,BDN,EXT;MDL:SCX-3400 Series;...
```

QPDL/SPL only — no PostScript, no PCL, no URF — so a generic driver cannot drive it.

## The solution

[SpliX](https://github.com/OpenPrinting/splix) is a GPL-2.0 CUPS driver for QPDL/SPL
printers. Release 2.0.2 (July 2026) added the Samsung SCX-3400 explicitly. It is C++
source, so it compiles natively for `arm64`:

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

## Install

```sh
sudo ./install.sh
```

This installs:

| Path | What |
| --- | --- |
| `/Library/Printers/SpliX/Filters/rastertoqpdl` | the filter (`/usr/libexec/cups/filter` is SIP-protected) |
| `/Library/Printers/PPDs/Contents/Resources/Samsung-SCX-3400-splix.ppd` | the PPD, with an absolute `*cupsFilter` path |

and creates a CUPS queue named `SCX3400`. The printer is auto-discovered with `lpinfo`;
pass a device URI explicitly if that fails:

```sh
lpinfo -v
sudo ./install.sh 'dnssd://Samsung%20SCX-3400%20Series%20(SEC00XXXXXXXXX)._printer._tcp.local./auto' SCX3400
```

Then remove the old, broken vendor queues and make the new one the default:

```sh
lpstat -p | grep -i samsung
sudo lpadmin -x Samsung_SCX_3400_Series__SECXXXXXXXXXXXX_
lpoptions -d SCX3400
```

Uninstall with `sudo ./uninstall.sh`.

## Build from source

`dist/` already contains a built filter, but you can rebuild it:

```sh
./build.sh
```

Requirements: Xcode Command Line Tools and Homebrew (for `jbigkit`).

`build.sh` downloads SpliX from OpenPrinting, applies three macOS fixes, builds, and
generates the PPD with the system `ppdc`:

1. macOS ships no `cups.pc`, so `tools/pkg-config` is a minimal shim answering for `cups`.
2. Upstream hardcodes MacPorts paths; they are rewritten to Homebrew for `jbigkit`.
3. `ppd/compile.sh` uses the GNU-only `sed -re`; BSD sed needs `-Ee`.

PPDs for every other SpliX-supported model land in `build/splix-master/ppd/out/`.

## Verify without printing

Run the whole filter chain by hand and inspect the output:

```sh
cupsfilter -m application/pdf /etc/hosts > /tmp/t.pdf
export PPD=dist/Samsung-SCX-3400-splix.ppd
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

## Troubleshooting

**Jobs still fail with `badarch-error`.** They are going to an old vendor queue. Check
`lpstat -d` and the queue name in `/var/log/cups/error_log`; delete the old queues and
set `SCX3400` as the default.

**`lpadmin` warns that printer drivers are deprecated.** Expected. CUPS will eventually
drop PPD support entirely; until then this works.

**Nothing comes out and the job completes.** Confirm the backend actually sent the data:
`lpstat -W completed -o` shows the byte count. A one-page job is roughly 15 KB.

## Scope

Printing only. The SCX-3400's scanner is a separate driver and is not addressed here.

## Licence

SpliX is GPL-2.0. `dist/rastertoqpdl` is a compiled SpliX binary and is covered by that
licence; the corresponding source is upstream at
[OpenPrinting/splix](https://github.com/OpenPrinting/splix), and the modifications
applied to it are the three `sed` edits in `build.sh`. The scripts in this repository
are GPL-2.0 as well.
