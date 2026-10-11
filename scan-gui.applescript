-- Scan.app: native dialogs in front of scan.sh, which is bundled in Resources.
-- Build with ./make-app.sh

on run
	set scanScript to quoted form of (POSIX path of (path to resource "scan.sh"))
	
	set modeChoice to choose from list {"Gray", "Color", "Lineart"} ¬
		with title "Scan" with prompt "Colour mode:" default items {"Gray"}
	if modeChoice is false then return
	set theMode to item 1 of modeChoice
	
	set dpiChoice to choose from list {"150", "300", "600", "1200"} ¬
		with title "Scan" with prompt "Resolution (dpi):" default items {"300"}
	if dpiChoice is false then return
	set theDPI to item 1 of dpiChoice
	
	set fmtChoice to choose from list {"PDF", "PNG", "JPEG"} ¬
		with title "Scan" with prompt "File format:" default items {"PDF"}
	if fmtChoice is false then return
	set theFormat to item 1 of fmtChoice
	if theFormat is "PDF" then
		set theExt to ".pdf"
	else if theFormat is "PNG" then
		set theExt to ".png"
	else
		set theExt to ".jpg"
	end if
	
	set stamp to do shell script "date +%Y%m%d-%H%M%S"
	try
		set outPath to POSIX path of (choose file name ¬
			with prompt "Save scan as:" default name ("scan-" & stamp & theExt))
	on error number -128
		return
	end try
	
	display notification (theDPI & " dpi, " & theMode) with title "Scanning…"
	try
		do shell script scanScript & " -r " & quoted form of theDPI & ¬
			" -m " & quoted form of theMode & " -o " & quoted form of outPath
	on error errText
		-- A connection that fails while the printer is plainly reachable is almost
		-- always the local-network privacy gate: a script run from Terminal inherits
		-- Terminal's permission, a fresh app has to be granted its own.
		display alert "Scan failed" message errText & return & return & ¬
			"If the printer is switched on, check System Settings › Privacy & Security › Local Network and switch Scan on, then try again." as critical
		return
	end try
	
	display notification (do shell script "basename " & quoted form of outPath) ¬
		with title "Scan finished"
	-- "open" from the shell, not Finder: driving Finder needs a separate automation
	-- permission, and without it the scan succeeds but the app cannot show it.
	do shell script "open " & quoted form of outPath
end run
