-- Launcher for the Homebrew mpv CLI: LaunchServices only binds file types to an app bundle.
-- __MPV_BIN__ is substituted by scripts/init_mac.sh (step mpv-app).
property mpvBin : "__MPV_BIN__"

on launchMpv(args)
	do shell script "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin " & quoted form of mpvBin & " --player-operation-mode=pseudo-gui " & args & " >/dev/null 2>&1 &"
end launchMpv

on run
	launchMpv("")
end run

on open theFiles
	set args to "--"
	repeat with f in theFiles
		set args to args & " " & quoted form of POSIX path of f
	end repeat
	launchMpv(args)
end open
